import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import '../../core/readers/epub_adapter.dart';

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
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  (Color, Color) get _colors => switch (theme) {
    EpubTheme.light => (Colors.white, Colors.black87),
    EpubTheme.dark => (const Color(0xff171717), Colors.white70),
    EpubTheme.sepia => (const Color(0xfffff3d6), const Color(0xff4b382a)),
  };

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors;
    final start = initialFraction;
    return Scaffold(
      backgroundColor: background,
      appBar: controls ? _appBar() : null,
      body: SafeArea(
        child: start == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Positioned.fill(
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
                  // Flutter owns the gestures: taps and swipes turn pages.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final direction = epubTapDirection(
                          d.localPosition.dx,
                          context.size?.width ?? 0,
                        );
                        if (direction == 0) {
                          setState(() => controls = !controls);
                        } else {
                          _turn(direction);
                        }
                      },
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() > 150) _turn(v < 0 ? 1 : -1);
                      },
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: start == null
          ? null
          : _statusBar(background, foreground),
    );
  }

  PreferredSizeWidget _appBar() => AppBar(
    title: Text(widget.session.title, maxLines: 1),
    actions: [
      IconButton(
        onPressed: _toc,
        tooltip: 'Sommaire',
        icon: const Icon(Icons.toc),
      ),
      IconButton(
        onPressed: _search,
        tooltip: 'Rechercher',
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: 'Ajouter un signet',
        onPressed: () {
          widget.database.addBookmark(
            widget.itemId,
            _locator.encode(),
            label: '${chapters[chapter].title} · p. ${page + 1}',
          );
          _toast('Signet ajouté');
        },
        icon: const Icon(Icons.bookmark_add_outlined),
      ),
      IconButton(
        tooltip: 'Affichage',
        onPressed: _settings,
        icon: const Icon(Icons.text_fields),
      ),
    ],
  );

  Widget _statusBar(Color background, Color foreground) {
    final style = TextStyle(color: foreground, fontSize: 12);
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controls) ...[
              LinearProgressIndicator(value: _bookProgress),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    chapters[chapter].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                Text(
                  'p. ${page + 1}/$pageCount · ${(_bookProgress * 100).round()} %',
                  style: style,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
    final input = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rechercher dans le livre'),
        content: TextField(
          controller: input,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
    input.dispose();
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
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          void update(VoidCallback change, {bool now = true}) {
            setSheet(change);
            setState(() {});
            if (now) apply();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
