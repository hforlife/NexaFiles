import 'package:flutter/services.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import '../storage/memory_content_source.dart';
import 'archive_core.dart';
import 'archive_safety_policy.dart';

/// RAR / 7z through the Android bridge. The native side keeps the archive open
/// and indexed for the whole session, so each page is a direct lookup.
class NativeArchiveAdapter implements ArchiveAdapter {
  NativeArchiveAdapter(this.container);
  final ContainerFormat container;
  static const _channel = MethodChannel('nexa_file/archives');
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canRandomAccess: true);
  @override
  bool supports(DetectedFormat format) => format.container == container;
  @override
  Future<ArchiveSession> open(
    ContentSource source,
    ArchiveSafetyPolicy safetyPolicy,
  ) async {
    final format = container == ContainerFormat.rar ? 'rar' : 'sevenZip';
    final opened = await _channel.invokeMapMethod<String, Object?>('open', {
      'uri': source.id,
      'format': format,
    });
    if (opened == null) throw StateError('Archive illisible');
    final session = _NativeSession(source, opened['session']! as int, [
      for (final m
          in (opened['entries']! as List).cast<Map<Object?, Object?>>())
        ArchiveEntry(
          path: m['name']! as String,
          compressedSize: (m['compressedSize'] as int?) ?? 0,
          uncompressedSize: (m['size'] as int?) ?? 0,
          isDirectory: m['directory'] == true,
        ),
    ]);
    try {
      safetyPolicy.validate(
        session.entries.map(
          (e) => (
            path: e.path,
            compressedSize: e.compressedSize,
            uncompressedSize: e.uncompressedSize,
          ),
        ),
      );
    } catch (_) {
      await session.close();
      rethrow;
    }
    return session;
  }
}

class _NativeSession implements ArchiveSession {
  _NativeSession(this.source, this.id, this.entries);
  final ContentSource source;
  final int id;
  final List<ArchiveEntry> entries;
  bool _closed = false;
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canRandomAccess: true);
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final bytes = await NativeArchiveAdapter._channel.invokeMethod<Uint8List>(
      'readEntry',
      {'session': id, 'name': entry.path},
    );
    if (bytes == null) throw StateError('Entrée illisible');
    return MemoryContentSource(
      id: '${source.id}#${entry.path}',
      displayName: entry.name,
      bytes: bytes,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await NativeArchiveAdapter._channel.invokeMethod<void>('close', {
      'session': id,
    });
  }
}
