import '../errors/app_failure.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';

enum ReaderType { pdf, epub, comic, image, audio, video, text }

abstract interface class ReaderSession {
  ContentSource get source;
  ReaderType get type;
  Future<void> dispose();
}

abstract interface class ReaderAdapter {
  Set<ContentKind> get supportedKinds;
  Future<ReaderSession> open(ContentSource source, DetectedFormat format);
}

class ReaderRegistry {
  ReaderRegistry([Iterable<ReaderAdapter> adapters = const []])
      : _adapters = [...adapters];
  final List<ReaderAdapter> _adapters;
  void register(ReaderAdapter adapter) => _adapters.add(adapter);
  ReaderAdapter? find(DetectedFormat format) {
    for (final adapter in _adapters) {
      if (adapter.supportedKinds.contains(format.content)) return adapter;
    }
    return null;
  }

  ReaderAdapter resolve(DetectedFormat format) =>
      _adapters.cast<ReaderAdapter?>().firstWhere(
          (a) => a!.supportedKinds.contains(format.content),
          orElse: () => null) ??
      (throw const UnsupportedFormatFailure());
  Future<ReaderSession> open(ContentSource source, DetectedFormat format) =>
      resolve(format).open(source, format);
}
