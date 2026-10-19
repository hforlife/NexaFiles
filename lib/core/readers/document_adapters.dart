import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'reader_core.dart';

Future<Uint8List> _bytes(ContentSource source) async {
  final output = BytesBuilder(copy: false);
  await for (final chunk in await source.openRead()) {
    output.add(chunk);
  }
  return output.takeBytes();
}

class PdfReaderAdapter implements ReaderAdapter {
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.pdf};
  @override
  Future<ReaderSession> open(
      ContentSource source, DetectedFormat format) async {
    final stopwatch = Stopwatch()..start();
    if (source is! MaterializedContentSource)
      throw const FormatException('Source PDF non matérialisable');
    final file = await source.materialize();
    const channel = MethodChannel('nexa_file/pdf');
    final count =
        await channel.invokeMethod<int>('pageCount', {'path': file.path});
    assert(() {
      print(
          'NexaFiles PDF open: ${stopwatch.elapsedMilliseconds} ms, ${file.lengthSync()} bytes');
      return true;
    }());
    if (count == null || count < 1) throw const FormatException('PDF vide');
    return PdfReaderSession(source, file, count);
  }
}

class PdfReaderSession implements ReaderSession {
  PdfReaderSession(this.source, this.file, this.pageCount);
  @override
  final ContentSource source;
  final File file;
  final int pageCount;
  static const _channel = MethodChannel('nexa_file/pdf');
  final Map<String, Future<Uint8List>> _renderCache = {};
  @override
  ReaderType get type => ReaderType.pdf;
  Future<Uint8List> render(int page, {int width = 1400}) =>
      _renderCache.putIfAbsent('$page@$width', () async {
        final result = await _channel.invokeMapMethod<Object?, Object?>(
            'render', {'path': file.path, 'page': page, 'width': width});
        final bytes = result?['bytes'] as Uint8List?;
        if (bytes == null || bytes.length < 100)
          throw const FormatException('Page PDF rendue vide');
        assert(() {
          print(
              '[PERF] PDF page ${page + 1}: native=${result?['durationMs']} ms, png=${bytes.length} bytes, bitmap=${result?['bitmapWidth']}x${result?['bitmapHeight']}');
          return true;
        }());
        while (_renderCache.length > 5) {
          _renderCache.remove(_renderCache.keys.first);
        }
        return bytes;
      });
  Future<List<PdfSearchResult>> search(String query) async =>
      ((await _channel.invokeListMethod<Object?>(
                  'search', {'path': file.path, 'query': query})) ??
              const [])
          .cast<Map<Object?, Object?>>()
          .map((e) => PdfSearchResult(e['page'] as int, e['snippet'] as String))
          .toList();
  @override
  Future<void> dispose() async {}
}

class PdfSearchResult {
  const PdfSearchResult(this.page, this.snippet);
  final int page;
  final String snippet;
}

class TextReaderAdapter implements ReaderAdapter {
  const TextReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds =>
      const {ContentKind.text, ContentKind.markdown};
  @override
  Future<ReaderSession> open(
      ContentSource source, DetectedFormat format) async {
    final data = await _bytes(source);
    final text = utf8.decode(data, allowMalformed: true);
    return TextReaderSession(
        source, text, format.content == ContentKind.markdown);
  }
}

class TextReaderSession implements ReaderSession {
  TextReaderSession(this.source, this.text, this.markdown);
  @override
  final ContentSource source;
  final String text;
  final bool markdown;
  @override
  ReaderType get type => ReaderType.text;
  @override
  Future<void> dispose() async {}
}

class ImageReaderAdapter implements ReaderAdapter {
  const ImageReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.image};
  @override
  Future<ReaderSession> open(
          ContentSource source, DetectedFormat format) async =>
      ImageReaderSession(source, await _bytes(source));
}

class ImageReaderSession implements ReaderSession {
  ImageReaderSession(this.source, this.bytes);
  @override
  final ContentSource source;
  final Uint8List bytes;
  @override
  ReaderType get type => ReaderType.image;
  @override
  Future<void> dispose() async {}
}

class EpubChapter {
  const EpubChapter(this.title, this.href, this.text);
  final String title, href, text;
}

class EpubReaderAdapter implements ReaderAdapter {
  const EpubReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.epub};
  @override
  Future<ReaderSession> open(
      ContentSource source, DetectedFormat format) async {
    final zip = ZipDecoder().decodeBytes(await _bytes(source), verify: true);
    final temp = await getTemporaryDirectory(),
        rootDir = Directory(p.join(temp.path, 'nexa_cache', 'readerTemp',
            'epub_${source.id.hashCode.toUnsigned(32)}'));
    if (await rootDir.exists()) await rootDir.delete(recursive: true);
    await rootDir.create(recursive: true);
    for (final entry in zip.files) {
      if (!entry.isFile) continue;
      final normalized = p.posix.normalize(entry.name);
      if (normalized.startsWith('../') ||
          normalized.startsWith('/') ||
          p.isAbsolute(normalized)) continue;
      final file = File(p.joinAll([rootDir.path, ...normalized.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content as List<int>, flush: false);
    }
    String? read(String name) {
      final f = zip.files.where((e) => e.name == name).firstOrNull;
      return f == null
          ? null
          : utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final container = read('META-INF/container.xml') ?? '';
    final rootFile =
        RegExp('full-path=["\']([^"\']+)').firstMatch(container)?.group(1);
    if (rootFile == null) throw const FormatException('EPUB invalide');
    final opf = read(rootFile) ?? '';
    final base = rootFile.contains('/')
        ? rootFile.substring(0, rootFile.lastIndexOf('/') + 1)
        : '';
    final title = _xmlText(opf, 'dc:title') ?? source.displayName;
    final author = _xmlText(opf, 'dc:creator');
    final manifest = <String, String>{};
    String? coverHref;
    for (final m
        in RegExp(r'<item\b[^>]*>', caseSensitive: false).allMatches(opf)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'id'), href = _attr(tag, 'href');
      if (id != null && href != null) {
        manifest[id] = href;
        if ((_attr(tag, 'properties') ?? '').split(' ').contains('cover-image'))
          coverHref = href;
      }
    }
    if (coverHref == null) {
      final coverId = RegExp(
              """<meta\\b[^>]*name=[\"']cover[\"'][^>]*content=[\"']([^\"']+)""",
              caseSensitive: false)
          .firstMatch(opf)
          ?.group(1);
      coverHref = coverId == null ? null : manifest[coverId];
    }
    final chapters = <EpubChapter>[];
    for (final m
        in RegExp(r'<itemref\b[^>]*>', caseSensitive: false).allMatches(opf)) {
      final id = _attr(m.group(0)!, 'idref'),
          href = id == null ? null : manifest[id];
      if (href == null) continue;
      final raw = read('$base$href');
      if (raw != null)
        chapters.add(EpubChapter(
            _htmlTitle(raw) ?? 'Chapitre ${chapters.length + 1}',
            href,
            _stripHtml(raw)));
    }
    if (chapters.isEmpty)
      throw const FormatException('EPUB sans contenu lisible');
    Uint8List? coverBytes;
    final coverFile = coverHref == null
        ? null
        : zip.files.where((e) => e.name == '$base$coverHref').firstOrNull;
    if (coverFile != null)
      coverBytes = Uint8List.fromList((coverFile.content as List<int>));
    return EpubReaderSession(
        source, title, author, chapters, coverBytes, rootDir.path, base);
  }
}

class EpubReaderSession implements ReaderSession {
  EpubReaderSession(this.source, this.title, this.author, this.chapters,
      this.coverBytes, this.rootPath, this.contentBase);
  @override
  final ContentSource source;
  final String title;
  final String? author;
  final List<EpubChapter> chapters;
  final Uint8List? coverBytes;
  final String rootPath, contentBase;
  String chapterPath(int index) => p.joinAll(
      [rootPath, ...('$contentBase${chapters[index].href}').split('/')]);
  @override
  ReaderType get type => ReaderType.epub;
  @override
  Future<void> dispose() async {}
}

String? _attr(String tag, String name) =>
    RegExp('$name=["\']([^"\']+)', caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);
String? _xmlText(String xml, String tag) =>
    RegExp('<$tag[^>]*>(.*?)</$tag>', caseSensitive: false, dotAll: true)
        .firstMatch(xml)
        ?.group(1)
        ?.replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
String? _htmlTitle(String html) =>
    _xmlText(html, 'title') ?? _xmlText(html, 'h1');
String _stripHtml(String html) => html
    .replaceAll(
        RegExp(r'<(script|style)\b[^>]*>.*?</\1>',
            caseSensitive: false, dotAll: true),
        '')
    .replaceAll(
        RegExp(r'<br\s*/?>|</p>|</h[1-6]>|</li>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
