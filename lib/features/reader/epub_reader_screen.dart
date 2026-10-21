import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import '../../core/readers/epub_adapter.dart';
import 'comic_reader_screen.dart'
    show ComicReadingDirection, ComicTapAction, comicTapAction;
import '../../shared/widgets/text_prompt.dart';
import 'reader_kit.dart';

enum EpubTheme { light, dark, sepia }

/// Whole-book progress from the chapter and the page inside it.
double epubBookProgress({
  required int chapter,
  required int chapterCount,
  required int page,
  required int pageCount,
}) {
  if (chapterCount <= 0) return 0;
  final inChapter = pageCount <= 0 ? 0 : (page + 1) / pageCount;
  return ((chapter + inChapter) / chapterCount).clamp(0, 1).toDouble();
}

/// -1 previous page, 1 next page, 0 toggle controls (outer 30 % turn pages).
int epubTapDirection(double dx, double width) {
  final position = width <= 0 ? .5 : dx / width;
  return position < .3 ? -1 : (position > .7 ? 1 : 0);
}

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen({
    super.key,
    required this.session,
    required this.database,
    required this.itemId,
  });
  final EpubReaderSession session;
  final AppDatabase database;
  final String itemId;
  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  MethodChannel? channel;
  int chapter = 0, page = 0, pageCount = 1;

  /// Position to open the first chapter at; null until restored.
  double? initialFraction;
  bool controls = true;
  double fontSize = 18, lineHeight = 1.5, margin = 20;
  String font = 'serif';
  EpubTheme theme = EpubTheme.light;
  ReaderPrefs readerPrefs = const ReaderPrefs();
  Timer? saveTimer;

  List<EpubChapter> get chapters => widget.session.chapters;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    fontSize = prefs.getDouble('epub.fontSize') ?? 18;
    lineHeight = prefs.getDouble('epub.lineHeight') ?? 1.5;
    margin = prefs.getDouble('epub.margin') ?? 20;
    font = prefs.getString('epub.font') ?? 'serif';
    theme =
        EpubTheme.values.asNameMap()[prefs.getString('epub.theme')] ??
        EpubTheme.light;
    readerPrefs = await ReaderPrefs.load();
    unawaited(applyReaderOrientation(readerPrefs.orientation));
    var fraction = 0.0;
    try {
      final saved = await widget.database.progress(widget.itemId);
      final locator = saved == null
          ? null
          : ReadingLocator.decode(saved.locator);
      if (locator is EpubLocator) {
        chapter = (locator.chapter ?? 0).clamp(0, chapters.length - 1);
        fraction = (locator.progress ?? 0).clamp(0, 1).toDouble();
      }
    } catch (_) {}
    if (mounted) setState(() => initialFraction = fraction);
  }

  Map<String, Object> get _style => {
    'textZoom': (fontSize / 18 * 100).round(),
    'theme': theme.name,
    'lineHeight': lineHeight,
    'margin': margin,
    'font': font,
  };

  Future<void> _onNative(MethodCall call) async {
    switch (call.method) {
      case 'position':
        final args = call.arguments as Map;
        setState(() {
          page = args['page'] as int;
          pageCount = args['count'] as int;
        });
        _scheduleSave();
      case 'edge':
        final direction = call.arguments as int;
        if (direction > 0) {
          if (chapter + 1 < chapters.length) {
            _openChapter(chapter + 1, 0);
          } else {
            _toast('Fin du livre');
          }
        } else if (chapter > 0) {
          _openChapter(chapter - 1, -1); // last page of the previous chapter
        }
    }
  }

  void _openChapter(int index, double fraction) {
    if (index < 0 || index >= chapters.length) return;
    if (index == chapter && fraction >= 0) {
      channel?.invokeMethod('go', {'fraction': fraction});
      return;
    }
    setState(() {
      chapter = index;
      page = 0;
    });
    channel?.invokeMethod('load', {
      'path': widget.session.chapterPath(index),
      'fraction': fraction,
    });
    _scheduleSave();
  }

  void _turn(int direction) =>
      channel?.invokeMethod(direction > 0 ? 'next' : 'prev');

  void _scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  EpubLocator get _locator => EpubLocator(
    'href:${chapters[chapter].href}',
    chapter,
    pageCount <= 0 ? 0 : page / pageCount,
  );

  double get _bookProgress => epubBookProgress(
    chapter: chapter,
    chapterCount: chapters.length,
    page: page,
    pageCount: pageCount,
  );

  Future<void> _save() => widget.database.saveProgress(
    widget.itemId,
    _locator.encode(),
    _bookProgress,
  );

  @override
  void dispose() {
    saveTimer?.cancel();
    if (initialFraction != null) _save();
    channel?.setMethodCallHandler(null);
    widget.session.dispose();
    releaseReaderOrientation();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  (Color, Color) get _colors => switch (theme) {
    EpubTheme.light => (Colors.white, Colors.black87),
    EpubTheme.dark => (const Color(0xff171717), Colors.white70),
    EpubTheme.sepia => (const Color(0xfffff3d6), const Color(0xff4b382a)),
  };

  Future<void> _addBookmark() async {
    await widget.database.addBookmark(
      widget.itemId,
      _locator.encode(),
      label: '${chapters[chapter].title} · p. ${page + 1}',
    );
    if (mounted) _toast('Signet ajouté');
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
    if (value is EpubLocator) {
      _openChapter(
        (value.chapter ?? 0).clamp(0, chapters.length - 1),
        (value.progress ?? 0).clamp(0, 1).toDouble(),
      );
    }
  }

  void _onTap(TapUpDetails d, Size size) {
    final action = comicTapAction(
      dx: d.localPosition.dx,
      dy: d.localPosition.dy,
      width: size.width,
      height: size.height,
      direction: ComicReadingDirection.leftToRight,
      layout: readerPrefs.tapLayout,
    );
    switch (action) {
      case ComicTapAction.toggleControls:
        setState(() => controls = !controls);
      case ComicTapAction.previous:
        _turn(-1);
      case ComicTapAction.next:
        _turn(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors;
    final start = initialFraction;
    return Scaffold(
      backgroundColor: background,
      body: start == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // The page area never changes size: showing the controls
                // would otherwise make the web view paginate the chapter
                // again on every tap.
                Positioned.fill(
                  child: SafeArea(
                    child: Column(
                      children: [
                        Expanded(
                          child: AndroidView(
                            viewType: 'nexa_file/epub',
                            creationParams: {
                              'root': widget.session.rootPath,
                              'path': widget.session.chapterPath(chapter),
                              'fraction': start,
                              'paginated': true,
                              ..._style,
                            },
                            creationParamsCodec: const StandardMessageCodec(),
                            onPlatformViewCreated: (id) =>
                                channel = MethodChannel('nexa_file/epub_$id')
                                  ..setMethodCallHandler(_onNative),
                          ),
                        ),
                        _statusLine(foreground),
                      ],
                    ),
                  ),
                ),
                // Flutter owns the gestures: taps and swipes turn pages.
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onTap(d, constraints.biggest),
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() > 150) _turn(v < 0 ? 1 : -1);
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ReaderFade(visible: controls, child: _topBar()),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ReaderFade(visible: controls, child: _bottomPanel()),
                ),
              ],
            ),
    );
  }

  Widget _topBar() => ReaderTopBar(
    title: widget.session.title,
    subtitle: chapters[chapter].title,
    actions: [
      IconButton(
        onPressed: _toc,
        tooltip: 'Sommaire',
        icon: const Icon(Icons.toc_rounded),
      ),
      IconButton(
        onPressed: _search,
        tooltip: 'Rechercher',
        icon: const Icon(Icons.search_rounded),
      ),
      IconButton(
        tooltip: 'Signets',
        onPressed: _bookmarks,
        icon: const Icon(Icons.bookmarks_outlined),
      ),
      IconButton(
        tooltip: 'Affichage',
        onPressed: _settings,
        icon: const Icon(Icons.text_fields_rounded),
      ),
    ],
  );

  /// Always visible, constant height: chapter and page.
  Widget _statusLine(Color foreground) {
    final style = TextStyle(
      color: foreground.withValues(alpha: .6),
      fontSize: 11.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                chapters[chapter].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Text('p. ${page + 1}/$pageCount', style: style),
          ],
        ),
      ),
    );
  }

  Widget _bottomPanel() => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 34),
    child: ReaderGlass(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Chapitre précédent',
            color: ReaderColors.text,
            onPressed: chapter > 0 ? () => _openChapter(chapter - 1, 0) : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _bookProgress,
                  minHeight: 5,
                  backgroundColor: ReaderColors.line,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Chapitre suivant',
            color: ReaderColors.text,
            onPressed: chapter + 1 < chapters.length
                ? () => _openChapter(chapter + 1, 0)
                : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          ReaderPageChip(label: '${(_bookProgress * 100).round()} %'),
        ],
      ),
    ),
  );

  void _toc() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            const ListTile(title: Text('Sommaire')),
            for (var i = 0; i < chapters.length; i++)
              ListTile(
                title: Text(chapters[i].title),
                selected: i == chapter,
                onTap: () {
                  Navigator.pop(c);
                  _openChapter(i, 0);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _search() async {
    final query = await showTextPrompt(
      context,
      title: 'Rechercher dans le livre',
      hint: 'Mot ou expression',
      confirm: 'Rechercher',
    );
    if (query == null || query.trim().isEmpty) return;
    final hit = await widget.session.search(query, fromChapter: chapter);
    if (!mounted) return;
    if (hit == null) {
      _toast('Aucun résultat');
    } else {
      _openChapter(hit.chapter, hit.fraction);
    }
  }

  Future<void> _settings() async {
    void apply() => channel?.invokeMethod('style', _style);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          void update(VoidCallback change, {bool now = true}) {
            setSheet(change);
            setState(() {});
            if (now) apply();
          }

          void setPrefs(ReaderPrefs value) {
            final rotate = value.orientation != readerPrefs.orientation;
            setSheet(() => readerPrefs = value);
            if (rotate) applyReaderOrientation(value.orientation);
            value.save();
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Affichage', style: Theme.of(c).textTheme.titleLarge),
                  const SheetLabel('Texte'),
                  Text('Taille ${fontSize.round()}'),
                  Slider(
                    value: fontSize,
                    min: 12,
                    max: 32,
                    onChanged: (v) => update(() => fontSize = v, now: false),
                    onChangeEnd: (_) => apply(),
                  ),
                  Text('Interligne ${lineHeight.toStringAsFixed(1)}'),
                  Slider(
                    value: lineHeight,
                    min: 1,
                    max: 2.2,
                    onChanged: (v) => update(() => lineHeight = v, now: false),
                    onChangeEnd: (_) => apply(),
                  ),
                  Text('Marges ${margin.round()}'),
                  Slider(
                    value: margin,
                    min: 8,
                    max: 48,
                    onChanged: (v) => update(() => margin = v, now: false),
                    onChangeEnd: (_) => apply(),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'serif', label: Text('Serif')),
                      ButtonSegment(
                        value: 'sans-serif',
                        label: Text('Sans-serif'),
                      ),
                    ],
                    selected: {font},
                    onSelectionChanged: (v) => update(() => font = v.first),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<EpubTheme>(
                    segments: const [
                      ButtonSegment(
                        value: EpubTheme.light,
                        label: Text('Clair'),
                      ),
                      ButtonSegment(
                        value: EpubTheme.dark,
                        label: Text('Sombre'),
                      ),
                      ButtonSegment(
                        value: EpubTheme.sepia,
                        label: Text('Sépia'),
                      ),
                    ],
                    selected: {theme},
                    onSelectionChanged: (v) => update(() => theme = v.first),
                  ),
                  const SheetLabel('Zones de changement de page'),
                  TapLayoutPicker(
                    value: readerPrefs.tapLayout,
                    onChanged: (v) =>
                        setPrefs(readerPrefs.copyWith(tapLayout: v)),
                  ),
                  const SheetLabel('Orientation de l’écran'),
                  OrientationPicker(
                    value: readerPrefs.orientation,
                    onChanged: (v) =>
                        setPrefs(readerPrefs.copyWith(orientation: v)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('epub.fontSize', fontSize);
    await prefs.setDouble('epub.lineHeight', lineHeight);
    await prefs.setDouble('epub.margin', margin);
    await prefs.setString('epub.font', font);
    await prefs.setString('epub.theme', theme.name);
  }
}
