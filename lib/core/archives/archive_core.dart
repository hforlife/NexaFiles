import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'archive_safety_policy.dart';

class ArchiveCapabilities {
  const ArchiveCapabilities(
      {this.canList = true,
      this.canReadEntry = true,
      this.canExtract = true,
      this.canCreate = false,
      this.canRandomAccess = false});
  final bool canList, canReadEntry, canExtract, canCreate, canRandomAccess;
}

class ArchiveEntry {
  const ArchiveEntry(
      {required this.path,
      required this.compressedSize,
      required this.uncompressedSize,
      required this.isDirectory});
  final String path;
  final int compressedSize, uncompressedSize;
  final bool isDirectory;
  String get name =>
      path.split('/').where((e) => e.isNotEmpty).lastOrNull ?? path;
}

abstract interface class ArchiveSession {
  ArchiveCapabilities get capabilities;
  Future<List<ArchiveEntry>> listEntries();
  Future<ContentSource> openEntry(ArchiveEntry entry);
  Future<void> close();
}

abstract interface class ArchiveAdapter {
  ArchiveCapabilities get capabilities;
  bool supports(DetectedFormat format);
  Future<ArchiveSession> open(
      ContentSource source, ArchiveSafetyPolicy safetyPolicy);
}

class ArchiveRegistry {
  ArchiveRegistry([Iterable<ArchiveAdapter> adapters = const []])
      : _adapters = [...adapters];
  final List<ArchiveAdapter> _adapters;
  void register(ArchiveAdapter adapter) => _adapters.add(adapter);
  ArchiveAdapter? find(DetectedFormat format) {
    for (final adapter in _adapters) {
      if (adapter.supports(format)) return adapter;
    }
    return null;
  }

  Future<ArchiveSession> open(ContentSource source, DetectedFormat format,
      {ArchiveSafetyPolicy safetyPolicy = const ArchiveSafetyPolicy()}) async {
    final adapter = find(format);
    if (adapter == null) throw StateError('Archive non prise en charge');
    return adapter.open(source, safetyPolicy);
  }
}
