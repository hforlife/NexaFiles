import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';
import '../../core/database/models.dart';
import '../../core/readers/document_adapters.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen(
      {super.key,
      required this.session,
      required this.database,
      required this.itemId,
      required this.title});
  final PdfReaderSession session;
  final AppDatabase database;
  final String itemId, title;
  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late PageController controller;
  int page = 0;
  bool vertical = true, controls = true;
  Timer? saveTimer;
  @override
  void initState() {
    super.initState();
    controller = PageController();
    _restore();
  }

  Future<void> _restore() async {
    final p = await widget.database.progress(widget.itemId);
    if (p != null) {
      try {
        final l = ReadingLocator.decode(p.locator);
        if (l is PdfLocator) {
          page = l.page.clamp(0, widget.session.pageCount - 1);
          controller = PageController(initialPage: page);
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
  }

  void _changed(int value) {
    setState(() => page = value);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() => widget.database.saveProgress(widget.itemId,
      PdfLocator(page).encode(), (page + 1) / widget.session.pageCount);
  @override
  void dispose() {
    saveTimer?.cancel();
    _save();
    controller.dispose();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff202124),
      appBar: controls
          ? AppBar(
              title: Text(widget.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                  IconButton(
                      tooltip: 'Rechercher',
                      onPressed: _search,
                      icon: const Icon(Icons.search)),
                  IconButton(
                      tooltip: 'Ajouter un signet',
                      onPressed: () {
                        widget.database.addBookmark(
                            widget.itemId, PdfLocator(page).encode(),
                            label: 'Page ${page + 1}');
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Signet ajouté')));
                      },
                      icon: const Icon(Icons.bookmark_add_outlined)),
                  IconButton(
                      tooltip: vertical ? 'Page unique' : 'Défilement vertical',
                      onPressed: () => setState(() => vertical = !vertical),
                      icon: Icon(vertical
                          ? Icons.menu_book_outlined
                          : Icons.view_agenda_outlined))
                ])
          : null,
      body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => controls = !controls),
          child: vertical
              ? _vertical()
              : PageView.builder(
                  controller: controller,
                  itemCount: widget.session.pageCount,
                  onPageChanged: _changed,
                  itemBuilder: (_, i) =>
                      _PdfPage(session: widget.session, index: i))),
      bottomNavigationBar: controls
          ? SafeArea(
              child: Container(
                  color: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Slider(
                        value: page.toDouble(),
                        max: (widget.session.pageCount - 1)
                            .toDouble()
                            .clamp(1, double.infinity),
                        onChanged: (v) => _jump(v.round())),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton.filledTonal(
                          tooltip: 'Page précédente',
                          onPressed: page > 0 ? () => _jump(page - 1) : null,
                          icon: const Icon(Icons.remove)),
                      SizedBox(
                          width: 120,
                          child: Text(
                              '${page + 1} / ${widget.session.pageCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600))),
                      IconButton.filledTonal(
                          tooltip: 'Page suivante',
                          onPressed: page + 1 < widget.session.pageCount
                              ? () => _jump(page + 1)
                              : null,
                          icon: const Icon(Icons.add))
                    ])
                  ])))
          : null);
  void _jump(int value) {
    final target = value.clamp(0, widget.session.pageCount - 1);
    controller.animateToPage(target,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    _changed(target);
  }

  Widget _vertical() => PageView.builder(
      scrollDirection: Axis.vertical,
      controller: controller,
      itemCount: widget.session.pageCount,
      onPageChanged: _changed,
      itemBuilder: (_, i) => _PdfPage(session: widget.session, index: i));
  Future<void> _search() async {
    final input = TextEditingController();
    final query = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Rechercher dans le PDF'),
                content: TextField(controller: input, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, input.text),
                      child: const Text('Rechercher'))
                ]));
    if (query == null || query.trim().isEmpty) return;
    if (!mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final results = await widget.session.search(query);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Aucun texte recherchable ou aucun résultat.')));
        return;
      }
      await showModalBottomSheet(
          context: context,
          builder: (c) => ListView(children: [
                ListTile(title: Text('${results.length} résultat(s)')),
                for (final r in results)
                  ListTile(
                      title: Text('Page ${r.page + 1}'),
                      subtitle: Text(r.snippet, maxLines: 3),
                      onTap: () {
                        Navigator.pop(c);
                        controller.jumpToPage(r.page);
                        _changed(r.page);
                      })
              ]));
    } catch (_) {
      if (mounted) {
        Navigator.maybePop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recherche impossible pour ce document.')));
      }
    }
  }
}

class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.session, required this.index});
  final PdfReaderSession session;
  final int index;
  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  Uint8List? bytes;
  Object? error;
  @override
  void initState() {
    super.initState();
    widget.session.render(widget.index).then((v) async {
      await decodeImageFromList(v);
      assert(() {
        debugPrint(
            'PDF widget received page=${widget.index} bytes=${v.length}');
        return true;
      }());
      if (mounted) setState(() => bytes = v);
    }).catchError((e) {
      if (mounted) setState(() => error = e);
    });
  }

  @override
  Widget build(BuildContext context) => error != null
      ? Center(
          child: Text('Page impossible à afficher\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)))
      : bytes == null
          ? const Center(child: CircularProgressIndicator())
          : SizedBox.expand(
              child: InteractiveViewer(
                  minScale: .7,
                  maxScale: 5,
                  child: Image.memory(bytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, e, __) => Center(
                          child: Text('Image PDF invalide: $e',
                              style: const TextStyle(color: Colors.white))))));
}

enum EpubTheme { light, dark, sepia }

class EpubReaderScreen extends StatefulWidget {
  const EpubReaderScreen(
      {super.key,
      required this.session,
      required this.database,
      required this.itemId});
  final EpubReaderSession session;
  final AppDatabase database;
  final String itemId;
  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  int chapter = 0, styleRevision = 0;
  double fontSize = 18, lineHeight = 1.5, margin = 20;
  String font = 'serif';
  EpubTheme theme = EpubTheme.light;
  Timer? timer;
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
    theme = EpubTheme.values.firstWhere(
        (e) => e.name == (prefs.getString('epub.theme') ?? 'light'),
        orElse: () => EpubTheme.light);
    final p = await widget.database.progress(widget.itemId);
    if (p != null) {
      try {
        final l = ReadingLocator.decode(p.locator);
        if (l is EpubLocator)
          chapter =
              (l.chapter ?? 0).clamp(0, widget.session.chapters.length - 1);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _go(int value) {
    setState(
        () => chapter = value.clamp(0, widget.session.chapters.length - 1));
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() => widget.database.saveProgress(
      widget.itemId,
      EpubLocator('href:${widget.session.chapters[chapter].href}', chapter)
          .encode(),
      (chapter + 1) / widget.session.chapters.length);
  @override
  void dispose() {
    timer?.cancel();
    _save();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = switch (theme) {
      EpubTheme.light => (Colors.white, Colors.black87),
      EpubTheme.dark => (const Color(0xff171717), Colors.white),
      EpubTheme.sepia => (const Color(0xfffff3d6), const Color(0xff4b382a))
    };
    return Scaffold(
        backgroundColor: colors.$1,
        appBar: AppBar(title: Text(widget.session.title), actions: [
          IconButton(
              onPressed: _toc,
              tooltip: 'Sommaire',
              icon: const Icon(Icons.toc)),
          IconButton(
              onPressed: _search,
              tooltip: 'Rechercher',
              icon: const Icon(Icons.search)),
          IconButton(
              onPressed: () {
                widget.database.addBookmark(
                    widget.itemId,
                    EpubLocator('href:${widget.session.chapters[chapter].href}',
                            chapter)
                        .encode(),
                    label: widget.session.chapters[chapter].title);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signet ajouté')));
              },
              icon: const Icon(Icons.bookmark_add_outlined)),
          IconButton(onPressed: _settings, icon: const Icon(Icons.text_fields))
        ]),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: AndroidView(
                  key: ValueKey('${chapter}_$styleRevision'),
                  viewType: 'nexa_file/epub',
                  creationParams: {
                    'root': widget.session.rootPath,
                    'path': widget.session.chapterPath(chapter),
                    'textZoom': (fontSize / 18 * 100).round(),
                    'theme': theme.name,
                    'lineHeight': lineHeight,
                    'margin': margin,
                    'font': font
                  },
                  creationParamsCodec: const StandardMessageCodec())),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
                onPressed: chapter > 0 ? () => _go(chapter - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            Text('${chapter + 1} / ${widget.session.chapters.length}',
                style: TextStyle(color: colors.$2)),
            IconButton(
                onPressed: chapter + 1 < widget.session.chapters.length
                    ? () => _go(chapter + 1)
                    : null,
                icon: const Icon(Icons.chevron_right))
          ])
        ])));
  }

  void _toc() {
    showModalBottomSheet(
        context: context,
        builder: (c) => ListView(children: [
              const ListTile(title: Text('Sommaire')),
              for (var i = 0; i < widget.session.chapters.length; i++)
                ListTile(
                    title: Text(widget.session.chapters[i].title),
                    selected: i == chapter,
                    onTap: () {
                      Navigator.pop(c);
                      _go(i);
                    })
            ]));
  }

  void _search() {
    final input = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Recherche dans le livre'),
                content: TextField(controller: input, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () {
                        final q = input.text.toLowerCase();
                        final i = widget.session.chapters.indexWhere(
                            (e) => e.text.toLowerCase().contains(q));
                        Navigator.pop(c);
                        if (i >= 0)
                          _go(i);
                        else
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Aucun résultat')));
                      },
                      child: const Text('Rechercher'))
                ]));
  }

  Future<void> _settings() async {
    final stopwatch = Stopwatch()..start();
    await showModalBottomSheet(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, setLocal) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Taille ${fontSize.round()}'),
                  Slider(
                      value: fontSize,
                      min: 12,
                      max: 32,
                      onChanged: (v) {
                        fontSize = v;
                        setLocal(() {});
                      }),
                  Text('Interligne ${lineHeight.toStringAsFixed(1)}'),
                  Slider(
                      value: lineHeight,
                      min: 1,
                      max: 2.2,
                      onChanged: (v) {
                        lineHeight = v;
                        setLocal(() {});
                      }),
                  Text('Marges ${margin.round()}'),
                  Slider(
                      value: margin,
                      min: 8,
                      max: 48,
                      onChanged: (v) {
                        margin = v;
                        setLocal(() {});
                      }),
                  DropdownButton<String>(
                      value: font,
                      items: const [
                        DropdownMenuItem(value: 'serif', child: Text('Serif')),
                        DropdownMenuItem(
                            value: 'sans-serif', child: Text('Sans-serif'))
                      ],
                      onChanged: (v) {
                        font = v!;
                        setLocal(() {});
                      }),
                  SegmentedButton<EpubTheme>(
                      segments: const [
                        ButtonSegment(
                            value: EpubTheme.light, label: Text('Clair')),
                        ButtonSegment(
                            value: EpubTheme.dark, label: Text('Sombre')),
                        ButtonSegment(
                            value: EpubTheme.sepia, label: Text('Sépia'))
                      ],
                      selected: {
                        theme
                      },
                      onSelectionChanged: (v) {
                        theme = v.first;
                        setLocal(() {});
                      })
                ]))));
    if (mounted) setState(() => styleRevision++);
    assert(() {
      print('NexaFiles EPUB settings: ${stopwatch.elapsedMilliseconds} ms');
      return true;
    }());
    final p = await SharedPreferences.getInstance();
    unawaited(p.setDouble('epub.fontSize', fontSize));
    unawaited(p.setDouble('epub.lineHeight', lineHeight));
    unawaited(p.setDouble('epub.margin', margin));
    unawaited(p.setString('epub.font', font));
    unawaited(p.setString('epub.theme', theme.name));
  }
}

class TextReaderScreen extends StatefulWidget {
  const TextReaderScreen(
      {super.key,
      required this.session,
      required this.database,
      required this.itemId,
      required this.title});
  final TextReaderSession session;
  final AppDatabase database;
  final String itemId, title;
  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  final scroll = ScrollController();
  double size = 17;
  bool dark = false;
  @override
  void initState() {
    super.initState();
    scroll.addListener(_progress);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = await widget.database.progress(widget.itemId);
      if (p != null && scroll.hasClients)
        scroll.jumpTo(p.fraction * scroll.position.maxScrollExtent);
    });
  }

  void _progress() {
    if (!scroll.hasClients) return;
    widget.database.saveProgress(
        widget.itemId,
        jsonEncode({'type': 'text', 'offset': scroll.offset}),
        scroll.position.maxScrollExtent == 0
            ? 0
            : scroll.offset / scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    scroll.dispose();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: dark ? const Color(0xff181818) : Colors.white,
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(onPressed: _search, icon: const Icon(Icons.search)),
        IconButton(
            onPressed: () => setState(() => dark = !dark),
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)),
        PopupMenuButton<double>(
            onSelected: (v) => setState(() => size = v),
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 15, child: Text('Petit')),
                  PopupMenuItem(value: 17, child: Text('Normal')),
                  PopupMenuItem(value: 21, child: Text('Grand'))
                ])
      ]),
      body: SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          child: SelectableText(_render(widget.session.text),
              style: TextStyle(
                  fontSize: size,
                  height: 1.55,
                  color: dark ? Colors.white : Colors.black87,
                  fontFamily: widget.session.markdown ? 'serif' : null))));
  String _render(String s) => widget.session.markdown
      ? s
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\*\*|__|`'), '')
      : s;
  void _search() {
    final input = TextEditingController();
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Rechercher'),
                content: TextField(controller: input),
                actions: [
                  FilledButton(
                      onPressed: () {
                        final i = widget.session.text
                            .toLowerCase()
                            .indexOf(input.text.toLowerCase());
                        Navigator.pop(c);
                        if (i < 0)
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Aucun résultat')));
                        else
                          scroll.jumpTo((i / widget.session.text.length) *
                              scroll.position.maxScrollExtent);
                      },
                      child: const Text('Rechercher'))
                ]));
  }
}

class ImageReaderScreen extends StatefulWidget {
  const ImageReaderScreen(
      {super.key,
      required this.session,
      required this.title,
      this.images = const [],
      this.storage,
      this.initialIndex = 0});
  final ImageReaderSession session;
  final String title;
  final List<StorageEntry> images;
  final StorageRepository? storage;
  final int initialIndex;
  @override
  State<ImageReaderScreen> createState() => _ImageReaderScreenState();
}

class _ImageReaderScreenState extends State<ImageReaderScreen> {
  late final PageController pages;
  bool controls = true;
  late int index;
  final cache = <int, Future<Uint8List>>{};
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    pages = PageController(initialPage: index);
    cache[index] = Future.value(widget.session.bytes);
  }

  @override
  void dispose() {
    pages.dispose();
    widget.session.dispose();
    super.dispose();
  }

  Future<Uint8List> _load(int i) => cache.putIfAbsent(i, () async {
        final source = widget.storage!.sourceFor(widget.images[i]),
            out = BytesBuilder(copy: false);
        await for (final chunk in await source.openRead()) {
          out.add(chunk);
        }
        return out.takeBytes();
      });
  @override
  Widget build(BuildContext context) {
    final count = widget.images.isEmpty ? 1 : widget.images.length,
        title = widget.images.isEmpty
            ? widget.title
            : widget.images[index].displayName;
    return Scaffold(
        backgroundColor: Colors.black,
        appBar: controls
            ? AppBar(
                backgroundColor: Colors.black,
                title: Text(title),
                actions: [
                    if (count > 1)
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(child: Text('${index + 1} / $count')))
                  ])
            : null,
        body: GestureDetector(
            onTap: () => setState(() => controls = !controls),
            child: PageView.builder(
                controller: pages,
                itemCount: count,
                onPageChanged: (v) {
                  setState(() => index = v);
                  for (final key
                      in cache.keys.where((k) => (k - v).abs() > 1).toList()) {
                    cache.remove(key);
                  }
                },
                itemBuilder: (_, i) => FutureBuilder<Uint8List>(
                    future: widget.images.isEmpty
                        ? Future.value(widget.session.bytes)
                        : _load(i),
                    builder: (_, snap) {
                      if (snap.hasError)
                        return const Center(
                            child: Text('Image impossible à ouvrir',
                                style: TextStyle(color: Colors.white)));
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return _ZoomImage(bytes: snap.data!);
                    }))));
  }
}

class _ZoomImage extends StatefulWidget {
  const _ZoomImage({required this.bytes});
  final Uint8List bytes;
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final transform = TransformationController();
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onDoubleTap: () => transform.value = transform.value == Matrix4.identity()
          ? Matrix4.diagonal3Values(2, 2, 1)
          : Matrix4.identity(),
      child: InteractiveViewer(
          transformationController: transform,
          minScale: .5,
          maxScale: 6,
          child:
              Center(child: Image.memory(widget.bytes, fit: BoxFit.contain))));
}
