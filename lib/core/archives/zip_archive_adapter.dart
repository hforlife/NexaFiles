import 'dart:io';
import 'package:archive/archive_io.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import '../storage/memory_content_source.dart';
import 'archive_core.dart';
import 'archive_safety_policy.dart';

class ZipArchiveAdapter implements ArchiveAdapter {
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canCreate: true, canRandomAccess: true);
  @override
  bool supports(DetectedFormat format) =>
      format.container == ContainerFormat.zip;
  @override
  Future<ArchiveSession> open(
      ContentSource source, ArchiveSafetyPolicy safetyPolicy) async {
    final file = await _materialize(source);
    final archive =
        ZipDecoder().decodeBuffer(InputFileStream(file.path), verify: true);
    final entries = archive.files
        .map((e) => ArchiveEntry(
            path: e.name,
            compressedSize: e.rawContent?.length ?? e.size,
            uncompressedSize: e.size,
            isDirectory: !e.isFile))
        .toList();
    safetyPolicy.validate(entries.map((e) => (
          path: e.path,
          compressedSize: e.compressedSize,
          uncompressedSize: e.uncompressedSize
        )));
    return _ZipSession(source, archive, entries);
  }

  Future<File> _materialize(ContentSource source) async {
    if (source is MaterializedContentSource) return source.materialize();
    final temp =
        File('${Directory.systemTemp.path}/nexa-${source.id.hashCode}.zip');
    final sink = temp.openWrite();
    await sink.addStream(await source.openRead());
    await sink.close();
    return temp;
  }
}

class _ZipSession implements ArchiveSession {
  _ZipSession(this.source, this.archive, this.entries);
  final ContentSource source;
  final Archive archive;
  final List<ArchiveEntry> entries;
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canCreate: true, canRandomAccess: true);
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final file = archive.files.firstWhere((e) => e.name == entry.path);
    return MemoryContentSource(
        id: '${source.id}#${entry.path}',
        displayName: entry.name,
        bytes: file.content as List<int>);
  }

  @override
  Future<void> close() async {
    for (final file in archive.files) {
      file.clear();
    }
  }
}
