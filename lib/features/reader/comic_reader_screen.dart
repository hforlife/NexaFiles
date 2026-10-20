import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';

enum ComicReadingMode { single, vertical, doublePage }

enum ComicReadingDirection { leftToRight, rightToLeft }

enum ComicFitMode { width, height, free }

int pageStepForMode(ComicReadingMode mode) =>
    mode == ComicReadingMode.doublePage ? 2 : 1;
int steppedComicPage({
  required int current,
  required int pageCount,
  required ComicReadingMode mode,
  required int direction,
}) => (current + pageStepForMode(mode) * direction).clamp(
  0,
  (pageCount - 1).clamp(0, pageCount),
);

enum ComicTapAction { previous, next, toggleControls }

/// Tap zones: outer 30 % turn pages, the centre toggles the controls.
/// In right-to-left (manga) reading the left edge goes forward.
ComicTapAction comicTapAction({
  required double dx,
  required double width,
  required ComicReadingDirection direction,
}) {
  final rtl = direction == ComicReadingDirection.rightToLeft;
  final position = width <= 0 ? .5 : dx / width;
  if (position < .3) return rtl ? ComicTapAction.next : ComicTapAction.previous;
  if (position > .7) return rtl ? ComicTapAction.previous : ComicTapAction.next;
  return ComicTapAction.toggleControls;
}

/// Pages are decoded close to screen resolution (1.5x keeps zoom sharp)
/// instead of full scan size; never upscaled.
ImageProvider comicPageImage(
  Uint8List bytes, {
  required Size box,
  required double pixelRatio,
  required ComicFitMode fit,
}) {
  const headroom = 1.5;
  final image = MemoryImage(bytes);
  return fit == ComicFitMode.height
      ? ResizeImage(
          image,
          height: (box.height * pixelRatio * headroom).round(),
          allowUpscaling: false,
        )
      : ResizeImage(
          image,
          width: (box.width * pixelRatio * headroom).round(),
          allowUpscaling: false,
        );
}

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen({
    super.key,
    required this.session,
    required this.database,
    required this.itemId,
    required this.title,
  });
  final ComicReaderSession session;
  final AppDatabase database;
  final String itemId, title;
  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  int count = 0, page = 0;
  bool controls = true, loading = true, zoomed = false;
  ComicReadingMode mode = ComicReadingMode.single;
  ComicReadingDirection direction = ComicReadingDirection.leftToRight;
  ComicFitMode fit = ComicFitMode.width;
  PageController? pageController;
  ScrollController? scrollController;
  Timer? saveTimer;
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initialize();
  }

  Future<void> _initialize() async {
    count = await widget.session.pages.pageCount;
    final prefs = await widget.database.readerPreferences(widget.itemId),
        global = await SharedPreferences.getInstance();
    mode = ComicReadingMode.values.byName(
      prefs?.mode ??
          global.getString('comic.default.mode') ??
          ComicReadingMode.single.name,
    );
    direction = ComicReadingDirection.values.byName(
      prefs?.direction ??
          global.getString('comic.default.direction') ??
          ComicReadingDirection.leftToRight.name,
    );
    fit = ComicFitMode.values.byName(
      prefs?.fit ??
          global.getString('comic.default.fit') ??
          ComicFitMode.width.name,
    );
    final progress = await widget.database.progress(widget.itemId);
    if (progress != null) {
      final locator = ReadingLocator.decode(progress.locator);
      if (locator is ComicLocator) {
        page = locator.page.clamp(0, (count - 1).clamp(0, count)).toInt();
      }
    }
    pageController = PageController(initialPage: _viewIndexForPage(page));
    scrollController = ScrollController(initialScrollOffset: page * 600.0)
      ..addListener(_verticalProgress);
    if (mounted) setState(() => loading = false);
    _preload();
  }

  int _viewIndexForPage(int value) => mode == ComicReadingMode.doublePage
      ? (value == 0 ? 0 : ((value - 1) ~/ 2) + 1)
      : value;
  int _pageForViewIndex(int value) => mode == ComicReadingMode.doublePage
      ? (value == 0 ? 0 : (value - 1) * 2 + 1)
      : value;
  int get _viewCount => mode == ComicReadingMode.doublePage
      ? (count <= 1 ? count : 1 + ((count - 1) / 2).ceil())
      : count;
  void _verticalProgress() {
    if (scrollController == null || !scrollController!.hasClients) return;
    final viewport = scrollController!.position.viewportDimension;
    if (viewport > 0) {
      _setPage(
        (scrollController!.offset / viewport)
            .round()
            .clamp(0, (count - 1).clamp(0, count))
            .toInt(),
      );
    }
  }

  void _setPage(int value) {
    if (value == page) return;
    setState(() => page = value);
    _preload();
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _preload() {
    final pages = widget.session.pages, from = page - 2, count = 6;
    unawaited(pages.preload(from, count).catchError((Object _) {}));
    if (mode == ComicReadingMode.vertical || !mounted) return;
    final screen = MediaQuery.sizeOf(context),
        box = mode == ComicReadingMode.doublePage
            ? Size(screen.width / 2, screen.height)
            : screen,
        ratio = MediaQuery.devicePixelRatioOf(context);
    for (final index in [page + 1, page + 2, page - 1]) {
      if (index < 0 || index >= this.count) continue;
      pages.getPage(index).then((p) {
        if (mounted) {
          precacheImage(
            comicPageImage(p.bytes, box: box, pixelRatio: ratio, fit: fit),
            context,
          );
        }
      }, onError: (Object _) {});
    }
  }

  void _onTap(TapUpDetails details) {
    if (mode == ComicReadingMode.vertical) {
      setState(() => controls = !controls);
      return;
    }
    final action = comicTapAction(
      dx: details.localPosition.dx,
      width: MediaQuery.sizeOf(context).width,
      direction: direction,
    );
    if (action == ComicTapAction.toggleControls) {
      setState(() => controls = !controls);
      return;
    }
    final step = action == ComicTapAction.next ? 1 : -1;
    final target = steppedComicPage(
      current: page,
      pageCount: count,
      mode: mode,
      direction: step,
    );
    if (target != page) _jump(target);
  }

  void _zoomChanged(bool value) {
    if (value != zoomed) setState(() => zoomed = value);
  }

  Future<void> _save() async {
    if (count == 0) return;
    await widget.database.saveProgress(
      widget.itemId,
      ComicLocator(page).encode(),
      (page + 1) / count,
    );
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    _save();
    pageController?.dispose();
    scrollController?.dispose();
    widget.session.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Indexation…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _onTap,
        child: Stack(
          children: [
            Positioned.fill(child: _content()),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (count == 0) {
      return const Center(
        child: Text(
          'Aucune page lisible',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (mode == ComicReadingMode.vertical) {
      return NotificationListener<ScrollNotification>(
        onNotification: (_) => false,
        child: ListView.builder(
          controller: scrollController,
          itemCount: count,
          itemBuilder: (_, i) => SizedBox(
            height: MediaQuery.sizeOf(context).height,
            child: _page(i),
          ),
        ),
      );
    }
    return PageView.builder(
      controller: pageController,
      itemCount: _viewCount,
      reverse: direction == ComicReadingDirection.rightToLeft,
      // While zoomed, horizontal drags pan the page instead of turning it.
      physics: zoomed ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (i) {
        zoomed = false;
        _setPage(_pageForViewIndex(i));
      },
      itemBuilder: (_, i) =>
          mode == ComicReadingMode.doublePage ? _spread(i) : _page(i),
    );
  }

  Widget _page(int index) => _Page(
    source: widget.session.pages,
    index: index,
    fit: fit,
    onZoomChanged: _zoomChanged,
  );

  Widget _spread(int index) {
    if (index == 0) return _page(0);
    final first = (index - 1) * 2 + 1,
        second = first + 1,
        pages = [first, if (second < count) second];
    if (direction == ComicReadingDirection.rightToLeft) {
      pages.replaceRange(0, pages.length, pages.reversed);
    }
    return Row(
      children: [for (final value in pages) Expanded(child: _page(value))],
    );
  }

  Widget _controls() => IgnorePointer(
    ignoring: !controls,
    child: AnimatedOpacity(
      opacity: controls ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Container(
                color: Colors.black87,
                child: ListTile(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  title: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: IconButton(
                    onPressed: _options,
                    icon: const Icon(Icons.tune, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      value: count <= 1 ? 0 : page.toDouble(),
                      min: 0,
                      max: (count - 1).clamp(0, count).toDouble(),
                      onChanged: (v) => _jump(v.round()),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Page précédente',
                          onPressed: page > 0
                              ? () => _jump(
                                  steppedComicPage(
                                    current: page,
                                    pageCount: count,
                                    mode: mode,
                                    direction: -1,
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            '${page + 1} / $count',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Page suivante',
                          onPressed: page + 1 < count
                              ? () => _jump(
                                  steppedComicPage(
                                    current: page,
                                    pageCount: count,
                                    mode: mode,
                                    direction: 1,
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  void _jump(int target) {
    zoomed = false;
    _setPage(target);
    if (mode == ComicReadingMode.vertical) {
      scrollController?.animateTo(
        target * MediaQuery.sizeOf(context).height,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      pageController?.animateToPage(
        _viewIndexForPage(target),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _options() {
    showModalBottomSheet(
      context: context,
      // Rebuilds the sheet so radios and switch reflect each change at once.
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Mode de lecture')),
              RadioGroup<ComicReadingMode>(
                groupValue: mode,
                onChanged: (v) => setSheet(() => _update(mode: v)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final value in ComicReadingMode.values)
                      RadioListTile<ComicReadingMode>(
                        value: value,
                        title: Text(_modeName(value)),
                      ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: direction == ComicReadingDirection.rightToLeft,
                title: const Text('Lecture droite → gauche'),
                onChanged: (v) => setSheet(
                  () => _update(
                    direction: v
                        ? ComicReadingDirection.rightToLeft
                        : ComicReadingDirection.leftToRight,
                  ),
                ),
              ),
              const ListTile(title: Text('Ajustement')),
              RadioGroup<ComicFitMode>(
                groupValue: fit,
                onChanged: (v) => setSheet(() => _update(fit: v)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final value in ComicFitMode.values)
                      RadioListTile<ComicFitMode>(
                        value: value,
                        title: Text(_fitName(value)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _update({
    ComicReadingMode? mode,
    ComicReadingDirection? direction,
    ComicFitMode? fit,
  }) {
    final watch = Stopwatch()..start();
    setState(() {
      this.mode = mode ?? this.mode;
      this.direction = direction ?? this.direction;
      this.fit = fit ?? this.fit;
      pageController?.dispose();
      pageController = PageController(initialPage: _viewIndexForPage(page));
    });
    assert(() {
      debugPrint(
        '[PERF] reader preference visual update = ${watch.elapsedMilliseconds} ms',
      );
      return true;
    }());
    unawaited(
      widget.database.saveReaderPreferences(
        widget.itemId,
        this.mode.name,
        this.direction.name,
        this.fit.name,
      ),
    );
  }

  String _modeName(ComicReadingMode value) => switch (value) {
    ComicReadingMode.single => 'Page unique',
    ComicReadingMode.vertical => 'Défilement vertical',
    ComicReadingMode.doublePage => 'Double page',
  };
  String _fitName(ComicFitMode value) => switch (value) {
    ComicFitMode.width => 'Ajuster largeur',
    ComicFitMode.height => 'Ajuster hauteur',
    ComicFitMode.free => 'Original / libre',
  };
}

class _Page extends StatelessWidget {
  const _Page({
    required this.source,
    required this.index,
    required this.fit,
    required this.onZoomChanged,
  });
  final ComicPageSource source;
  final int index;
  final ComicFitMode fit;
  final ValueChanged<bool> onZoomChanged;
  @override
  Widget build(BuildContext context) => FutureBuilder<ComicPage>(
    future: source.getPage(index),
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 48,
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return _ZoomComicImage(
        bytes: snapshot.data!.bytes,
        fit: fit,
        onZoomChanged: onZoomChanged,
      );
    },
  );
}

class _ZoomComicImage extends StatefulWidget {
  const _ZoomComicImage({
    required this.bytes,
    required this.fit,
    required this.onZoomChanged,
  });
  final Uint8List bytes;
  final ComicFitMode fit;
  final ValueChanged<bool> onZoomChanged;
  @override
  State<_ZoomComicImage> createState() => _ZoomComicImageState();
}

class _ZoomComicImageState extends State<_ZoomComicImage> {
  final controller = TransformationController();
  Offset? _doubleTapAt;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_reportZoom);
  }

  void _reportZoom() {
    final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Double tap zooms 2.5x around the tapped point, or resets.
  void _toggleZoom() {
    if (_zoomed) {
      controller.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final at = _doubleTapAt ?? Offset.zero;
    controller.value = Matrix4.identity()
      ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image(
            image: comicPageImage(
              widget.bytes,
              box: constraints.biggest,
              pixelRatio: MediaQuery.devicePixelRatioOf(context),
              fit: widget.fit,
            ),
            fit: switch (widget.fit) {
              ComicFitMode.width => BoxFit.fitWidth,
              ComicFitMode.height => BoxFit.fitHeight,
              ComicFitMode.free => BoxFit.contain,
            },
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    ),
  );
}
