import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../shared/widgets/text_prompt.dart';
import 'reader_kit.dart';
import 'package:flutter/services.dart';
import '../../core/database/app_database.dart';
import '../../core/readers/document_adapters.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';

export 'epub_reader_screen.dart';
export 'pdf_reader_screen.dart';

class TextReaderScreen extends StatefulWidget {
  const TextReaderScreen({
    super.key,
    required this.session,
    required this.database,
    required this.itemId,
    required this.title,
    this.file,
  });
  final TextReaderSession session;
  final AppDatabase database;
  final String itemId, title;

  /// Local file behind the text; editing is offered when it is set.
  final File? file;
  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  /// Above this size the editor would be sluggish: reading only.
  static const _editLimit = 2 * 1024 * 1024;
  final scroll = ScrollController();
  late final editor = TextEditingController(text: widget.session.text);
  late String text = widget.session.text;
  double size = 17;
  bool dark = false, editing = false, saving = false;

  bool get dirty => editing && editor.text != text;
  bool get canEdit => widget.file != null && text.length <= _editLimit;

  @override
  void initState() {
    super.initState();
    scroll.addListener(_progress);
    editor.addListener(() {
      if (editing) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = await widget.database.progress(widget.itemId);
      if (p != null && scroll.hasClients) {
        scroll.jumpTo(p.fraction * scroll.position.maxScrollExtent);
      }
    });
  }

  void _progress() {
    if (!scroll.hasClients || editing) return;
    widget.database.saveProgress(
      widget.itemId,
      jsonEncode({'type': 'text', 'offset': scroll.offset}),
      scroll.position.maxScrollExtent == 0
          ? 0
          : scroll.offset / scroll.position.maxScrollExtent,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    editor.dispose();
    widget.session.dispose();
    super.dispose();
  }

  /// Writes to a temporary file first, then replaces the original: a crash
  /// mid-save never leaves a half-written file.
  Future<bool> _save() async {
    final file = widget.file;
    if (file == null) return false;
    setState(() => saving = true);
    try {
      final temp = File('${file.path}.nexa-tmp');
      await temp.writeAsString(editor.text, flush: true);
      await temp.rename(file.path);
      if (!mounted) return true;
      setState(() {
        text = editor.text;
        saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fichier enregistré')));
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $e')),
        );
      }
      return false;
    }
  }

  /// Leaving with unsaved changes: save, discard or stay.
  Future<bool> _confirmLeave() async {
    if (!dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Voulez-vous enregistrer vos modifications ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('Ignorer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (choice == 'save') return _save();
    return choice == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? Colors.white : Colors.black87;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: dark ? const Color(0xff181818) : Colors.white,
        appBar: AppBar(
          backgroundColor: dark ? const Color(0xff181818) : Colors.white,
          foregroundColor: foreground,
          title: Text(editing ? 'Modifier' : widget.title, maxLines: 1),
          actions: editing
              ? [
                  IconButton(
                    tooltip: 'Annuler les modifications',
                    onPressed: () => setState(() {
                      editor.text = text;
                      editing = false;
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: saving || !dirty ? null : _save,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text('Enregistrer'),
                    ),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Rechercher',
                    onPressed: _search,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Modifier',
                      onPressed: () => setState(() => editing = true),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  IconButton(
                    tooltip: dark ? 'Fond clair' : 'Fond sombre',
                    onPressed: () => setState(() => dark = !dark),
                    icon: Icon(
                      dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    ),
                  ),
                  PopupMenuButton<double>(
                    tooltip: 'Taille du texte',
                    icon: const Icon(Icons.format_size_rounded),
                    onSelected: (v) => setState(() => size = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 15, child: Text('Petit')),
                      PopupMenuItem(value: 17, child: Text('Normal')),
                      PopupMenuItem(value: 21, child: Text('Grand')),
                    ],
                  ),
                ],
        ),
        body: editing
            ? TextField(
                controller: editor,
                maxLines: null,
                expands: true,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: size - 2,
                  height: 1.5,
                  color: foreground,
                ),
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              )
            : SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  _render(text),
                  style: TextStyle(
                    fontSize: size,
                    height: 1.55,
                    color: foreground,
                    fontFamily: widget.session.markdown ? 'serif' : null,
                  ),
                ),
              ),
      ),
    );
  }

  String _render(String s) => widget.session.markdown
      ? s
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
            .replaceAll(RegExp(r'\*\*|__|`'), '')
      : s;

  Future<void> _search() async {
    final query = await showTextPrompt(
      context,
      title: 'Rechercher',
      confirm: 'Rechercher',
    );
    if (query == null || query.isEmpty || !mounted) return;
    final i = text.toLowerCase().indexOf(query.toLowerCase());
    if (i < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Aucun résultat')));
    } else if (scroll.hasClients) {
      scroll.jumpTo((i / text.length) * scroll.position.maxScrollExtent);
    }
  }
}

class ImageReaderScreen extends StatefulWidget {
  const ImageReaderScreen({
    super.key,
    required this.session,
    required this.title,
    this.images = const [],
    this.storage,
    this.initialIndex = 0,
  });
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
  bool controls = true, zoomed = false;
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
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => controls = !controls),
              child: PageView.builder(
                controller: pages,
                itemCount: count,
                allowImplicitScrolling: true,
                // While zoomed, horizontal drags pan the photo instead.
                physics: zoomed ? const NeverScrollableScrollPhysics() : null,
                onPageChanged: (v) {
                  setState(() {
                    index = v;
                    zoomed = false;
                  });
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
                    if (snap.hasError) {
                      return const Center(
                        child: Text(
                          'Image impossible à ouvrir',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _ZoomImage(
                      bytes: snap.data!,
                      onZoomChanged: (v) {
                        if (v != zoomed) setState(() => zoomed = v);
                      },
                    );
                  },
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ReaderFade(
              visible: controls,
              child: ReaderTopBar(
                title: title,
                subtitle: count > 1 ? '${index + 1} / $count' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomImage extends StatefulWidget {
  const _ZoomImage({required this.bytes, required this.onZoomChanged});
  final Uint8List bytes;
  final ValueChanged<bool> onZoomChanged;
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  final transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    transform.addListener(_report);
  }

  /// Panning is only needed (and only enabled) once the photo is zoomed;
  /// otherwise the swipe belongs to the gallery.
  void _report() {
    final zoomed = transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

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
      minScale: 1,
      maxScale: 6,
      panEnabled: _zoomed,
      // Decoded near screen resolution (2x for zoom): full-size camera
      // photos would otherwise stall each swipe.
      child: Center(
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth:
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context) *
                      2)
                  .round(),
        ),
      ),
    ),
  );
}
