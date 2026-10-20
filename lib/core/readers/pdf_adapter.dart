import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:pdfrx/pdfrx.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'reader_core.dart';

/// PDF through PDFium (pdfrx): continuous scrolling, sharp zoom, text search
/// and selection, rendered in-process without a platform channel.
class PdfReaderAdapter implements ReaderAdapter {
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.pdf};
  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async {
    if (source is! MaterializedContentSource) {
      throw const FormatException('Source PDF non matérialisable');
    }
    final file = await source.materialize();
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(file.path);
    if (document.pages.isEmpty) {
      await document.dispose();
      throw const FormatException('PDF vide');
    }
    return PdfReaderSession(source, document);
  }
}

class PdfReaderSession implements ReaderSession {
  PdfReaderSession(this.source, this.document);
  @override
  final ContentSource source;

  /// Owned by the session: viewers must not dispose it.
  final PdfDocument document;
  int get pageCount => document.pages.length;
  @override
  ReaderType get type => ReaderType.pdf;

  /// PNG of page [index] (0-based) at [width] px, used for covers.
  Future<Uint8List> renderThumbnail(int index, {int width = 300}) async {
    final page = document.pages[index];
    final image = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: width * page.height / page.width,
      backgroundColor: 0xffffffff,
    );
    if (image == null) throw const FormatException('Page PDF rendue vide');
    try {
      final picture = await image.createImage();
      try {
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('Page PDF rendue vide');
        return data.buffer.asUint8List();
      } finally {
        picture.dispose();
      }
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> dispose() => document.dispose();
}
