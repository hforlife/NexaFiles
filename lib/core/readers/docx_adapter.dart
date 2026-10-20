import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'docx_converter.dart';
import 'reader_core.dart';

/// Word (.docx) read in-app: converted once to HTML in the reader cache and
/// shown by the sandboxed document WebView.
class DocxReaderAdapter implements ReaderAdapter {
  const DocxReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.officeWord};
  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in await source.openRead()) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    final fallback = p.basenameWithoutExtension(source.displayName);
    // XML parsing of large documents stays off the UI isolate.
    final document = await Isolate.run(
      () => convertDocx(bytes, fallbackTitle: fallback),
    );
    final temp = await getTemporaryDirectory();
    final root = Directory(
      p.join(
        temp.path,
        'nexa_cache',
        'readerTemp',
        'docx_${source.id.hashCode.toUnsigned(32)}',
      ),
    );
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
    for (final MapEntry(key: name, value: data) in document.media.entries) {
      final file = File(p.joinAll([root.path, ...name.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data);
    }
    final page = File(p.join(root.path, 'index.html'));
    await page.writeAsString(document.html);
    return DocxReaderSession(source, document.title, root.path, page.path);
  }
}

class DocxReaderSession implements ReaderSession {
  DocxReaderSession(this.source, this.title, this.rootPath, this.htmlPath);
  @override
  final ContentSource source;
  final String title, rootPath, htmlPath;
  @override
  ReaderType get type => ReaderType.document;
  @override
  Future<void> dispose() async {
    try {
      await Directory(rootPath).delete(recursive: true);
    } catch (_) {}
  }
}
