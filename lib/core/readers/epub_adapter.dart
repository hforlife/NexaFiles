import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'epub_package.dart';
import 'reader_core.dart';

export 'epub_package.dart' show EpubChapter;

/// FNV-1a: unlike String.hashCode it is stable across runs, so extracted
/// books are found again in the cache.
String stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

class EpubMetadata {
  const EpubMetadata(this.title, this.author, this.coverBytes);
  final String? title, author;
  final Uint8List? coverBytes;
}

class EpubReaderAdapter implements ReaderAdapter {
  const EpubReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.epub};

  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async {
    final file = await _localFile(source);
    final stat = await file.stat();
    final temp = await getTemporaryDirectory();
    final root = p.join(
      temp.path,
      'nexa_cache',
      'readerTemp',
      'epub_${stableHash('${file.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}')}',
    );
    // Extracted once per file version; reopening the book costs only parsing.
    final opened = await Isolate.run(() => _openExtracted(file.path, root));
    final cover = opened.package.coverHref == null
        ? null
        : File(p.joinAll([root, ...opened.package.coverHref!.split('/')]));
    return EpubReaderSession(
      source,
      opened.package.title ?? p.basenameWithoutExtension(source.displayName),
      opened.package.author,
      opened.package.chapters,
      cover != null && await cover.exists() ? await cover.readAsBytes() : null,
      root,
    );
  }

  /// Title, author and cover only, straight from the archive (no extraction):
  /// what the library scanner needs.
  static Future<EpubMetadata> readMetadata(File file) => Isolate.run(() {
    final input = InputFileStream(file.path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      String? read(String path) {
        final entry = zip.findFile(path);
        final bytes = entry?.readBytes();
        return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
      }

      final package = _package(read);
      final cover = package.coverHref == null
          ? null
          : zip.findFile(package.coverHref!)?.readBytes();
      return EpubMetadata(package.title, package.author, cover);
    } finally {
      input.closeSync();
    }
  });

  static Future<File> _localFile(ContentSource source) async {
    if (source is MaterializedContentSource) return source.materialize();
    final temp = File(
      p.join(
        (await getTemporaryDirectory()).path,
        'nexa-${stableHash(source.id)}.epub',
      ),
    );
    final sink = temp.openWrite();
    await sink.addStream(await source.openRead());
    await sink.close();
    return temp;
  }
}

EpubPackage _package(String? Function(String path) read) {
  final container = read('META-INF/container.xml');
  final opfPath = container == null ? null : epubRootFile(container);
  final opf = opfPath == null ? null : read(opfPath);
  if (opfPath == null || opf == null) {
    throw const FormatException('EPUB invalide');
  }
  final package = parseEpubPackage(opfPath, opf, read);
  if (package.chapters.isEmpty) {
    throw const FormatException('EPUB sans contenu lisible');
  }
  return package;
}

/// Runs in an isolate: extracts the book into [root] unless already done,
/// then parses the package from disk.
({EpubPackage package}) _openExtracted(String path, String root) {
  final marker = File(p.join(root, '.complete'));
  if (!marker.existsSync()) {
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final input = InputFileStream(path);
    try {
      for (final entry in ZipDecoder().decodeStream(input)) {
        if (!entry.isFile) continue;
        final name = p.posix.normalize(entry.name);
        if (name.startsWith('../') || p.posix.isAbsolute(name)) continue;
        final out = File(p.joinAll([root, ...name.split('/')]));
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(entry.readBytes() ?? const []);
      }
    } finally {
      input.closeSync();
    }
    marker.writeAsStringSync('ok');
  }
  String? read(String name) {
    final file = File(p.joinAll([root, ...name.split('/')]));
    if (!file.existsSync()) return null;
    return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
  }

  return (package: _package(read));
}

/// Position of a search hit: chapter index and where in it (0–1).
typedef EpubSearchHit = ({int chapter, double fraction});

class EpubReaderSession implements ReaderSession {
  EpubReaderSession(
    this.source,
    this.title,
    this.author,
    this.chapters,
    this.coverBytes,
    this.rootPath,
  );
  @override
  final ContentSource source;
  final String title;
  final String? author;
  final List<EpubChapter> chapters;
  final Uint8List? coverBytes;
  final String rootPath;
  final _texts = <int, String>{};

  String chapterPath(int index) =>
      p.joinAll([rootPath, ...chapters[index].href.split('/')]);

  /// Plain text of a chapter, read on first need only.
  Future<String> chapterText(int index) async =>
      _texts[index] ??= epubPlainText(
        utf8.decode(
          await File(chapterPath(index)).readAsBytes(),
          allowMalformed: true,
        ),
      );

  /// Next occurrence of [query] from [fromChapter] onward, wrapping around.
  Future<EpubSearchHit?> search(String query, {int fromChapter = 0}) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (var step = 0; step < chapters.length; step++) {
      final index = (fromChapter + step) % chapters.length;
      final text = (await chapterText(index)).toLowerCase();
      final at = text.indexOf(needle);
      if (at >= 0) {
        return (
          chapter: index,
          fraction: text.isEmpty ? 0.0 : at / text.length,
        );
      }
    }
    return null;
  }

  @override
  ReaderType get type => ReaderType.epub;

  /// Extraction stays in the reader cache for fast reopening.
  @override
  Future<void> dispose() async {}
}
