import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
int steppedComicPage(
        {required int current,
        required int pageCount,
        required ComicReadingMode mode,
        required int direction}) =>
    (current + pageStepForMode(mode) * direction)
        .clamp(0, (pageCount - 1).clamp(0, pageCount));

class ComicReaderScreen extends StatefulWidget {
  const ComicReaderScreen(
      {super.key,
      required this.session,
      required this.database,
      required this.itemId,
      required this.title});
  final ComicReaderSession session;
  final AppDatabase database;
  final String itemId, title;
  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  int count = 0, page = 0;
  bool controls = true, loading = true;
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
    mode = ComicReadingMode.values.byName(prefs?.mode ??
        global.getString('comic.default.mode') ??
        ComicReadingMode.single.name);
    direction = ComicReadingDirection.values.byName(prefs?.direction ??
        global.getString('comic.default.direction') ??
        ComicReadingDirection.leftToRight.name);
    fit = ComicFitMode.values.byName(prefs?.fit ??
        global.getString('comic.default.fit') ??
        ComicFitMode.width.name);
    final progress = await widget.database.progress(widget.itemId);
    if (progress != null) {
      final locator = ReadingLocator.decode(progress.locator);
      if (locator is ComicLocator)
        page = locator.page.clamp(0, (count - 1).clamp(0, count)).toInt();
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
    if (viewport > 0)
      _setPage((scrollController!.offset / viewport)
          .round()
          .clamp(0, (count - 1).clamp(0, count))
          .toInt());
  }

  void _setPage(int value) {
    if (value == page) return;
    setState(() => page = value);
    _preload();
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _preload() => widget.session.pages.preload(page - 1, 4);
  Future<void> _save() async {
    if (count == 0) return;
    await widget.database.saveProgress(
        widget.itemId, ComicLocator(page).encode(), (page + 1) / count);
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
    if (loading)
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Indexation…', style: TextStyle(color: Colors.white))
          ])));
    return Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => controls = !controls),
            child: Stack(
                children: [Positioned.fill(child: _content()), _controls()])));
  }

  Widget _content() {
    if (count == 0)
      return const Center(
          child: Text('Aucune page lisible',
              style: TextStyle(color: Colors.white)));
    if (mode == ComicReadingMode.vertical)
      return NotificationListener<ScrollNotification>(
          onNotification: (_) => false,
          child: ListView.builder(
              controller: scrollController,
              itemCount: count,
              itemBuilder: (_, i) => SizedBox(
                  height: MediaQuery.sizeOf(context).height,
                  child: _Page(
                      source: widget.session.pages, index: i, fit: fit))));
    return PageView.builder(
        controller: pageController,
        itemCount: _viewCount,
        reverse: direction == ComicReadingDirection.rightToLeft,
        onPageChanged: (i) => _setPage(_pageForViewIndex(i)),
        itemBuilder: (_, i) => mode == ComicReadingMode.doublePage
            ? _spread(i)
            : _Page(source: widget.session.pages, index: i, fit: fit));
  }

  Widget _spread(int index) {
    if (index == 0)
      return _Page(source: widget.session.pages, index: 0, fit: fit);
    final first = (index - 1) * 2 + 1,
        second = first + 1,
        pages = [first, if (second < count) second];
    if (direction == ComicReadingDirection.rightToLeft)
      pages.replaceRange(0, pages.length, pages.reversed);
    return Row(children: [
      for (final value in pages)
        Expanded(
            child: _Page(source: widget.session.pages, index: value, fit: fit))
    ]);
  }

  Widget _controls() => IgnorePointer(
      ignoring: !controls,
      child: AnimatedOpacity(
          opacity: controls ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Stack(children: [
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
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.white)),
                            title: Text(widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white)),
                            trailing: IconButton(
                                onPressed: _options,
                                icon: const Icon(Icons.tune,
                                    color: Colors.white)))))),
            Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: SafeArea(
                    child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(16)),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Slider(
                              value: count <= 1 ? 0 : page.toDouble(),
                              min: 0,
                              max: (count - 1).clamp(0, count).toDouble(),
                              onChanged: (v) => _jump(v.round())),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                    tooltip: 'Page précédente',
                                    onPressed: page > 0
                                        ? () => _jump(steppedComicPage(
                                            current: page,
                                            pageCount: count,
                                            mode: mode,
                                            direction: -1))
                                        : null,
                                    icon: const Icon(Icons.remove)),
                                SizedBox(
                                    width: 120,
                                    child: Text('${page + 1} / $count',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600))),
                                IconButton.filledTonal(
                                    tooltip: 'Page suivante',
                                    onPressed: page + 1 < count
                                        ? () => _jump(steppedComicPage(
                                            current: page,
                                            pageCount: count,
                                            mode: mode,
                                            direction: 1))
                                        : null,
                                    icon: const Icon(Icons.add))
                              ])
                        ]))))
          ])));
  void _jump(int target) {
    _setPage(target);
    if (mode == ComicReadingMode.vertical) {
      scrollController?.animateTo(target * MediaQuery.sizeOf(context).height,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      pageController?.animateToPage(_viewIndexForPage(target),
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _options() {
    showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Mode de lecture')),
              for (final value in ComicReadingMode.values)
                RadioListTile(
                    value: value,
                    groupValue: mode,
                    title: Text(_modeName(value)),
                    onChanged: (v) => _update(mode: v)),
              const Divider(),
              SwitchListTile(
                  value: direction == ComicReadingDirection.rightToLeft,
                  title: const Text('Lecture droite → gauche'),
                  onChanged: (v) => _update(
                      direction: v
                          ? ComicReadingDirection.rightToLeft
                          : ComicReadingDirection.leftToRight)),
              const ListTile(title: Text('Ajustement')),
              for (final value in ComicFitMode.values)
                RadioListTile(
                    value: value,
                    groupValue: fit,
                    title: Text(_fitName(value)),
                    onChanged: (v) => _update(fit: v))
            ])));
  }

  void _update(
      {ComicReadingMode? mode,
      ComicReadingDirection? direction,
      ComicFitMode? fit}) {
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
          '[PERF] reader preference visual update = ${watch.elapsedMilliseconds} ms');
      return true;
    }());
    unawaited(widget.database.saveReaderPreferences(
        widget.itemId, this.mode.name, this.direction.name, this.fit.name));
  }

  String _modeName(ComicReadingMode value) => switch (value) {
        ComicReadingMode.single => 'Page unique',
        ComicReadingMode.vertical => 'Défilement vertical',
        ComicReadingMode.doublePage => 'Double page'
      };
  String _fitName(ComicFitMode value) => switch (value) {
        ComicFitMode.width => 'Ajuster largeur',
        ComicFitMode.height => 'Ajuster hauteur',
        ComicFitMode.free => 'Original / libre'
      };
}

class _Page extends StatelessWidget {
  const _Page({required this.source, required this.index, required this.fit});
  final ComicPageSource source;
  final int index;
  final ComicFitMode fit;
  @override
  Widget build(BuildContext context) => FutureBuilder<ComicPage>(
      future: source.getPage(index),
      builder: (_, snapshot) {
        if (snapshot.hasError)
          return const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 48));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return _ZoomComicImage(bytes: snapshot.data!.bytes, fit: fit);
      });
}

class _ZoomComicImage extends StatefulWidget {
  const _ZoomComicImage({required this.bytes, required this.fit});
  final Uint8List bytes;
  final ComicFitMode fit;
  @override
  State<_ZoomComicImage> createState() => _ZoomComicImageState();
}

class _ZoomComicImageState extends State<_ZoomComicImage> {
  final controller = TransformationController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.memory(widget.bytes,
        fit: switch (widget.fit) {
          ComicFitMode.width => BoxFit.fitWidth,
          ComicFitMode.height => BoxFit.fitHeight,
          ComicFitMode.free => BoxFit.contain
        },
        gaplessPlayback: true);
    return GestureDetector(
        onDoubleTap: () {
          final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
          controller.value = zoomed
              ? Matrix4.identity()
              : Matrix4.diagonal3Values(2.5, 2.5, 1);
        },
        child: InteractiveViewer(
            transformationController: controller,
            minScale: 1,
            maxScale: 5,
            panEnabled: true,
            child: Center(child: image)));
  }
}
