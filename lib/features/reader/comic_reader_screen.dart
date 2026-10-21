import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import 'reader_kit.dart';

export 'reader_kit.dart' show ComicTapLayout;

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

/// Maps a tap to an action according to the chosen [layout].
/// In right-to-left (manga) reading the zones are mirrored horizontally,
/// so the left edge goes forward.
ComicTapAction comicTapAction({
  required double dx,
  required double width,
  required ComicReadingDirection direction,
  double dy = 0,
  double height = 0,
  ComicTapLayout layout = ComicTapLayout.edges,
}) {
  var x = width <= 0 ? .5 : (dx / width).clamp(0.0, 1.0);
  final y = height <= 0 ? .5 : (dy / height).clamp(0.0, 1.0);
  if (direction == ComicReadingDirection.rightToLeft) x = 1 - x;
  switch (layout) {
    case ComicTapLayout.off:
      return ComicTapAction.toggleControls;
    case ComicTapLayout.edges:
      if (x < .3) return ComicTapAction.previous;
      if (x > .7) return ComicTapAction.next;
      return ComicTapAction.toggleControls;
    case ComicTapLayout.lShape:
      final centre = x >= 1 / 3 && x <= 2 / 3 && y >= 1 / 3 && y <= 2 / 3;
      if (centre) return ComicTapAction.toggleControls;
      return x < 1 / 3 || y < 1 / 3
          ? ComicTapAction.previous
          : ComicTapAction.next;
    case ComicTapLayout.kindle:
      if (y < .18) return ComicTapAction.toggleControls;
      return x < .3 ? ComicTapAction.previous : ComicTapAction.next;
  }
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
  ReaderPrefs prefs = const ReaderPrefs();
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
    this.prefs = await ReaderPrefs.load();
    unawaited(applyReaderOrientation(this.prefs.orientation));
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
    final size = MediaQuery.sizeOf(context);
    final action = comicTapAction(
      dx: details.localPosition.dx,
      dy: details.localPosition.dy,
      width: size.width,
      height: size.height,
      direction: direction,
      layout: prefs.tapLayout,
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
    releaseReaderOrientation();
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
          cacheExtent: MediaQuery.sizeOf(context).height * 2,
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
      // Builds the neighbouring pages ahead of time: turning is instant.
      allowImplicitScrolling: true,
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
    doubleTapZoom: prefs.doubleTapZoom,
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

  Widget _controls() => Stack(
    children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: ReaderFade(
          visible: controls,
          child: ReaderTopBar(
            title: widget.title,
            subtitle:
                '${_modeName(mode)} · ${direction == ComicReadingDirection.rightToLeft ? 'Droite → gauche' : 'Gauche → droite'}',
            actions: [
              IconButton(
                tooltip: 'Ajouter un signet',
                onPressed: _addBookmark,
                icon: const Icon(Icons.bookmark_add_outlined),
              ),
              IconButton(
                tooltip: 'Signets',
                onPressed: _bookmarks,
                icon: const Icon(Icons.bookmarks_outlined),
              ),
              IconButton(
                tooltip: 'Options de lecture',
                onPressed: _options,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ReaderFade(
          visible: controls,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ReaderGlass(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Page précédente',
                    color: ReaderColors.text,
                    onPressed: page > 0 ? () => _step(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    // The slider follows the reading direction.
                    child: Directionality(
                      textDirection:
                          direction == ComicReadingDirection.rightToLeft
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Slider(
                        value: count <= 1 ? 0 : page.toDouble(),
                        max: (count - 1).clamp(1, count).toDouble(),
                        onChanged: count > 1 ? (v) => _jump(v.round()) : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Page suivante',
                    color: ReaderColors.text,
                    onPressed: page + 1 < count ? () => _step(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  ReaderPageChip(label: '${page + 1} / $count'),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  void _step(int delta) => _jump(
    steppedComicPage(
      current: page,
      pageCount: count,
      mode: mode,
      direction: delta,
    ),
  );

  Future<void> _addBookmark() async {
    await widget.database.addBookmark(
      widget.itemId,
      ComicLocator(page).encode(),
      label: 'Page ${page + 1}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Signet ajouté à la page ${page + 1}')),
    );
  }

  Future<void> _bookmarks() async {
    final locator = await showBookmarksSheet(
      context,
      database: widget.database,
      itemId: widget.itemId,
      onAdd: _addBookmark,
    );
    if (locator == null) return;
    final value = ReadingLocator.decode(locator);
    if (value is ComicLocator) {
      _jump(value.page.clamp(0, (count - 1).clamp(0, count)).toInt());
    }
  }

  void _setPrefs(ReaderPrefs value) {
    final rotate = value.orientation != prefs.orientation;
    setState(() => prefs = value);
    if (rotate) applyReaderOrientation(value.orientation);
    value.save();
  }

  void _jump(int target) {
    zoomed = false;
    _setPage(target);
    if (mode == ComicReadingMode.vertical) {
      scrollController?.animateTo(
        target * MediaQuery.sizeOf(context).height,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      pageController?.animateToPage(
        _viewIndexForPage(target),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _options() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Rebuilds the sheet so each control reflects changes at once.
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void apply(VoidCallback change) => setSheet(change);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Options de lecture',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SheetLabel('Mode'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ComicReadingMode>(
                      showSelectedIcon: false,
                      segments: [
                        for (final v in ComicReadingMode.values)
                          ButtonSegment(
                            value: v,
                            icon: Icon(switch (v) {
                              ComicReadingMode.single =>
                                Icons.crop_portrait_rounded,
                              ComicReadingMode.vertical =>
                                Icons.view_day_rounded,
                              ComicReadingMode.doublePage =>
                                Icons.menu_book_rounded,
                            }),
                            label: Text(_modeShort(v)),
                          ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (v) =>
                          apply(() => _update(mode: v.first)),
                    ),
                  ),
                  const SheetLabel('Sens de lecture'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ComicReadingDirection>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ComicReadingDirection.leftToRight,
                          icon: Icon(Icons.arrow_forward_rounded),
                          label: Text('BD / Comics'),
                        ),
                        ButtonSegment(
                          value: ComicReadingDirection.rightToLeft,
                          icon: Icon(Icons.arrow_back_rounded),
                          label: Text('Manga'),
                        ),
                      ],
                      selected: {direction},
                      onSelectionChanged: (v) =>
                          apply(() => _update(direction: v.first)),
                    ),
                  ),
                  const SheetLabel('Ajustement'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ComicFitMode>(
                      showSelectedIcon: false,
                      segments: [
                        for (final v in ComicFitMode.values)
                          ButtonSegment(value: v, label: Text(_fitName(v))),
                      ],
                      selected: {fit},
                      onSelectionChanged: (v) =>
                          apply(() => _update(fit: v.first)),
                    ),
                  ),
                  const SheetLabel('Zones de changement de page'),
                  TapLayoutPicker(
                    value: prefs.tapLayout,
                    onChanged: (v) =>
                        apply(() => _setPrefs(prefs.copyWith(tapLayout: v))),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    value: prefs.doubleTapZoom,
                    title: const Text('Zoom au double tap'),
                    subtitle: const Text(
                      'Ajoute un court délai aux taps simples. Le pincement '
                      'fonctionne toujours.',
                    ),
                    onChanged: (v) => apply(
                      () => _setPrefs(prefs.copyWith(doubleTapZoom: v)),
                    ),
                  ),
                  const SheetLabel('Orientation de l’écran'),
                  OrientationPicker(
                    value: prefs.orientation,
                    onChanged: (v) =>
                        apply(() => _setPrefs(prefs.copyWith(orientation: v))),
                  ),
                ],
              ),
            ),
          );
        },
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
  String _modeShort(ComicReadingMode value) => switch (value) {
    ComicReadingMode.single => 'Page',
    ComicReadingMode.vertical => 'Vertical',
    ComicReadingMode.doublePage => 'Double',
  };
  String _fitName(ComicFitMode value) => switch (value) {
    ComicFitMode.width => 'Largeur',
    ComicFitMode.height => 'Hauteur',
    ComicFitMode.free => 'Libre',
  };
}

class _Page extends StatelessWidget {
  const _Page({
    required this.source,
    required this.index,
    required this.fit,
    required this.doubleTapZoom,
    required this.onZoomChanged,
  });
  final ComicPageSource source;
  final int index;
  final ComicFitMode fit;
  final bool doubleTapZoom;
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
        return const Center(
          child: CircularProgressIndicator(color: Colors.white38),
        );
      }
      return _ZoomComicImage(
        bytes: snapshot.data!.bytes,
        fit: fit,
        doubleTapZoom: doubleTapZoom,
        onZoomChanged: onZoomChanged,
      );
    },
  );
}

class _ZoomComicImage extends StatefulWidget {
  const _ZoomComicImage({
    required this.bytes,
    required this.fit,
    required this.doubleTapZoom,
    required this.onZoomChanged,
  });
  final Uint8List bytes;
  final ComicFitMode fit;
  final bool doubleTapZoom;
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
      // Registered only when enabled: a double-tap recognizer makes every
      // single tap wait for the double-tap timeout before turning the page.
      onDoubleTapDown: widget.doubleTapZoom
          ? (d) => _doubleTapAt = d.localPosition
          : null,
      onDoubleTap: widget.doubleTapZoom ? _toggleZoom : null,
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
