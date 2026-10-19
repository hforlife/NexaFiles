import 'package:flutter/services.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import '../storage/memory_content_source.dart';
import 'archive_core.dart';
import 'archive_safety_policy.dart';

class NativeArchiveAdapter implements ArchiveAdapter {
  NativeArchiveAdapter(this.container);
  final ContainerFormat container;
  static const _channel = MethodChannel('nexa_file/archives');
  @override
  ArchiveCapabilities get capabilities =>
      ArchiveCapabilities(canRandomAccess: container == ContainerFormat.rar);
  @override
  bool supports(DetectedFormat format) => format.container == container;
  @override
  Future<ArchiveSession> open(
      ContentSource source, ArchiveSafetyPolicy safetyPolicy) async {
    final format = container == ContainerFormat.rar ? 'rar' : 'sevenZip';
    final rows = await _channel.invokeListMethod<Object?>(
            'list', {'uri': source.id, 'format': format}) ??
        [];
    final entries = rows
        .cast<Map<Object?, Object?>>()
        .map((m) => ArchiveEntry(
            path: m['name']! as String,
            compressedSize: (m['compressedSize'] as int?) ?? 0,
            uncompressedSize: (m['size'] as int?) ?? 0,
            isDirectory: m['directory'] == true))
        .toList();
    safetyPolicy.validate(entries.map((e) => (
          path: e.path,
          compressedSize: e.compressedSize,
          uncompressedSize: e.uncompressedSize
        )));
    return _NativeSession(source, format, entries, capabilities);
  }
}

class _NativeSession implements ArchiveSession {
  _NativeSession(this.source, this.format, this.entries, this.capabilities);
  final ContentSource source;
  final String format;
  final List<ArchiveEntry> entries;
  @override
  final ArchiveCapabilities capabilities;
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final bytes = await NativeArchiveAdapter._channel.invokeMethod<Uint8List>(
        'readEntry', {'uri': source.id, 'format': format, 'name': entry.path});
    if (bytes == null) throw StateError('Entrée illisible');
    return MemoryContentSource(
        id: '${source.id}#${entry.path}',
        displayName: entry.name,
        bytes: bytes);
  }

  @override
  Future<void> close() async {}
}
