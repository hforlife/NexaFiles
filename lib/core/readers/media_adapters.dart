import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'reader_core.dart';

class MediaReaderAdapter implements ReaderAdapter {
  const MediaReaderAdapter();
  @override
  Set<ContentKind> get supportedKinds => const {
    ContentKind.audio,
    ContentKind.video,
  };
  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async => MediaReaderSession(source, format.content);
}

class MediaReaderSession implements ReaderSession {
  MediaReaderSession(this.source, this.kind);
  @override
  final ContentSource source;
  final ContentKind kind;
  @override
  ReaderType get type =>
      kind == ContentKind.audio ? ReaderType.audio : ReaderType.video;
  @override
  Future<void> dispose() async {}
}
