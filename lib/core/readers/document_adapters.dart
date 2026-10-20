import 'dart:convert';
import 'dart:typed_data';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'reader_core.dart';

export 'docx_adapter.dart';
export 'epub_adapter.dart';
export 'pdf_adapter.dart';

Future<Uint8List> _bytes(ContentSource source) async {
  final output = BytesBuilder(copy: false);
  await for (final chunk in await source.openRead()) {
    output.add(chunk);
  }
  return output.takeBytes();
}

class TextReaderAdapter implements ReaderAdapter {
  const TextReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {
    ContentKind.text,
    ContentKind.markdown,
  };
  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async {
    final data = await _bytes(source);
    final text = utf8.decode(data, allowMalformed: true);
    return TextReaderSession(
      source,
      text,
      format.content == ContentKind.markdown,
    );
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
    ContentSource source,
    DetectedFormat format,
  ) async => ImageReaderSession(source, await _bytes(source));
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
