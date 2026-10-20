import 'dart:io';
import 'package:archive/archive_io.dart';
import '../errors/app_failure.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import '../storage/memory_content_source.dart';
import 'archive_core.dart';
import 'archive_safety_policy.dart';

/// ZIP/CBZ access by random access: opening reads only the central directory,
/// each entry is inflated on demand and nothing is kept once returned.
class ZipArchiveAdapter implements ArchiveAdapter {
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canCreate: true, canRandomAccess: true);
  @override
  bool supports(DetectedFormat format) =>
      format.container == ContainerFormat.zip;
  @override
  Future<ArchiveSession> open(
    ContentSource source,
    ArchiveSafetyPolicy safetyPolicy,
  ) async {
    final file = await _materialize(source);
    final input = InputFileStream(file.path);
    try {
      final headers = {
        for (final header in (ZipDirectory()..read(input)).fileHeaders)
          header.filename: header,
      };
      final entries = [
        for (final header in headers.values)
          ArchiveEntry(
            path: header.filename,
            compressedSize: header.compressedSize,
            uncompressedSize: header.uncompressedSize,
            isDirectory: header.filename.endsWith('/'),
          ),
      ];
      safetyPolicy.validate(
        entries.map(
          (e) => (
            path: e.path,
            compressedSize: e.compressedSize,
            uncompressedSize: e.uncompressedSize,
          ),
        ),
      );
      return _ZipSession(source, input, headers, entries);
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  Future<File> _materialize(ContentSource source) async {
    if (source is MaterializedContentSource) return source.materialize();
    final temp = File(
      '${Directory.systemTemp.path}/nexa-${source.id.hashCode}.zip',
    );
    final sink = temp.openWrite();
    await sink.addStream(await source.openRead());
    await sink.close();
    return temp;
  }
}

class _ZipSession implements ArchiveSession {
  _ZipSession(this.source, this.input, this.headers, this.entries);
  final ContentSource source;
  final InputFileStream input;
  final Map<String, ZipFileHeader> headers;
  final List<ArchiveEntry> entries;
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canCreate: true, canRandomAccess: true);
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final header = headers[entry.path];
    if (header == null) throw const ArchiveFailure('Entrée absente');
    // ZipFile.getStream() inflates on every call and keeps nothing cached,
    // so pages read earlier do not accumulate in memory.
    final file = header.file;
    if (file == null) throw const ArchiveFailure('Entrée illisible');
    final data = file.getStream().toUint8List();
    if (getCrc32(data) != header.crc32) throw const CorruptedFileFailure();
    return MemoryContentSource(
      id: '${source.id}#${entry.path}',
      displayName: entry.name,
      bytes: data,
    );
  }

  @override
  Future<void> close() async => input.closeSync();
}
