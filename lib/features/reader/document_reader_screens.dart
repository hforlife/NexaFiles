import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  });
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
      if (p != null && scroll.hasClients) {
        scroll.jumpTo(p.fraction * scroll.position.maxScrollExtent);
      }
    });
  }

  void _progress() {
    if (!scroll.hasClients) return;
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
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: dark ? const Color(0xff181818) : Colors.white,
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(onPressed: _search, icon: const Icon(Icons.search)),
        IconButton(
          onPressed: () => setState(() => dark = !dark),
          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
        ),
        PopupMenuButton<double>(
          onSelected: (v) => setState(() => size = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 15, child: Text('Petit')),
            PopupMenuItem(value: 17, child: Text('Normal')),
            PopupMenuItem(value: 21, child: Text('Grand')),
          ],
        ),
      ],
    ),
    body: SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        _render(widget.session.text),
        style: TextStyle(
          fontSize: size,
          height: 1.55,
          color: dark ? Colors.white : Colors.black87,
          fontFamily: widget.session.markdown ? 'serif' : null,
        ),
      ),
    ),
  );
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
              final i = widget.session.text.toLowerCase().indexOf(
                input.text.toLowerCase(),
              );
              Navigator.pop(c);
              if (i < 0) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Aucun résultat')));
              } else {
                scroll.jumpTo(
                  (i / widget.session.text.length) *
                      scroll.position.maxScrollExtent,
                );
              }
            },
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
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
                    child: Center(child: Text('${index + 1} / $count')),
                  ),
              ],
            )
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
              return _ZoomImage(bytes: snap.data!);
            },
          ),
        ),
      ),
    );
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
      child: Center(child: Image.memory(widget.bytes, fit: BoxFit.contain)),
    ),
  );
}
