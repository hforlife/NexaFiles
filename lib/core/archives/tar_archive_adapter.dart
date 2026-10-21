import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../errors/app_failure.dart';
import '../formats/detected_format.dart';
import '../storage/content_source.dart';
import 'archive_core.dart';
import 'archive_safety_policy.dart';

/// Compression wrapping a file: gzip, bzip2, xz, or none (plain tar).
enum StreamCompression { none, gzip, bzip2, xz }

/// Detects gzip / bzip2 / xz from the first bytes.
StreamCompression streamCompressionOf(List<int> head) {
  bool starts(List<int> magic) =>
      head.length >= magic.length &&
      Iterable<int>.generate(magic.length).every((i) => head[i] == magic[i]);
  if (starts(const [0x1f, 0x8b])) return StreamCompression.gzip;
  if (starts(const [0x42, 0x5a, 0x68])) return StreamCompression.bzip2;
  if (starts(const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00])) {
    return StreamCompression.xz;
  }
  return StreamCompression.none;
}

/// Recognises a tar header: "ustar" at offset 257 (POSIX), or failing that
/// a valid header checksum (old v7 tarballs carry no magic).
bool isTarHeader(List<int> block) {
  if (block.length < 512) return false;
  if (String.fromCharCodes(block.sublist(257, 262)) == 'ustar') return true;
  // Checksum: octal at 148..155, computed with that field as spaces.
  final field = String.fromCharCodes(
    block.sublist(148, 156),
  ).replaceAll(RegExp(r'[\x00 ]'), '');
  final stored = int.tryParse(field, radix: 8);
  if (stored == null || stored == 0) return false;
  var sum = 0;
  for (var i = 0; i < 512; i++) {
    sum += i >= 148 && i < 156 ? 0x20 : block[i];
  }
  return sum == stored;
}

/// .tar, .tar.gz / .tgz, .tar.bz2 / .tbz2, .tar.xz / .txz, and single
/// compressed files (.gz, .bz2, .xz) shown as a one-entry archive.
/// The outer compression is undone to a temporary file in a background
/// isolate, so large tarballs never sit in memory.
class TarFamilyAdapter implements ArchiveAdapter {
  @override
  ArchiveCapabilities get capabilities => const ArchiveCapabilities();

  @override
  bool supports(DetectedFormat format) => const {
    ContainerFormat.tar,
    ContainerFormat.gzip,
    ContainerFormat.bzip2,
    ContainerFormat.xz,
  }.contains(format.container);

  @override
  Future<ArchiveSession> open(
    ContentSource source,
    ArchiveSafetyPolicy safetyPolicy, {
    String? password,
  }) async {
    if (source is! MaterializedContentSource) {
      throw const ArchiveFailure('Archive non accessible');
    }
    final file = await source.materialize();
    final head = await _read(file, 6);
    final compression = streamCompressionOf(head);
    var tarPath = file.path;
    File? temp;
    if (compression != StreamCompression.none) {
      temp = File(
        p.join(
          Directory.systemTemp.path,
          'nexa-tar-${file.path.hashCode.toUnsigned(32)}-'
          '${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      final from = file.path, to = temp.path;
      try {
        await Isolate.run(() => _decompress(from, to, compression));
      } catch (e) {
        if (temp.existsSync()) temp.deleteSync();
        throw ArchiveFailure('Décompression impossible', e);
      }
      tarPath = to;
    }
    final block = await _read(File(tarPath), 512);
    if (!isTarHeader(block)) {
      // Not a tarball: a single compressed file (e.g. notes.txt.gz).
      if (temp == null) {
        throw const UnsupportedFormatFailure('Archive TAR illisible');
      }
      final name = _strip(source.displayName);
      final size = await temp.length();
      return _SingleFileSession(
        ArchiveEntry(
          path: name,
          compressedSize: await file.length(),
          uncompressedSize: size,
          isDirectory: false,
        ),
        temp,
      );
    }
    final input = InputFileStream(tarPath);
    try {
      final archive = TarDecoder().decodeStream(input);
      final entries = [
        for (final f in archive)
          if (f.name.isNotEmpty)
            ArchiveEntry(
              path: f.name,
              compressedSize: f.size,
              uncompressedSize: f.size,
              isDirectory: !f.isFile,
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
      return _TarSession(
        input,
        {for (final f in archive) f.name: f},
        entries,
        temp,
      );
    } catch (e) {
      input.closeSync();
      if (temp != null && temp.existsSync()) temp.deleteSync();
      rethrow;
    }
  }

  static Future<List<int>> _read(File file, int count) async {
    final raf = await file.open();
    try {
      return await raf.read(count);
    } finally {
      await raf.close();
    }
  }

  /// "photos.tar.gz" → "photos.tar", "notes.txt.gz" → "notes.txt".
  static String _strip(String name) {
    final lower = name.toLowerCase();
    for (final ext in const ['.gz', '.bz2', '.xz', '.tgz', '.tbz2', '.txz']) {
      if (lower.endsWith(ext)) {
        final base = name.substring(0, name.length - ext.length);
        return ext.startsWith('.t') && ext.length > 3 ? '$base.tar' : base;
      }
    }
    return '$name.out';
  }
}

void _decompress(String from, String to, StreamCompression compression) {
  final input = InputFileStream(from);
  final output = OutputFileStream(to);
  try {
    final ok = switch (compression) {
      StreamCompression.gzip => GZipDecoder().decodeStream(input, output),
      StreamCompression.bzip2 => BZip2Decoder().decodeStream(input, output),
      StreamCompression.xz => XZDecoder().decodeStream(input, output),
      StreamCompression.none => true,
    };
    if (!ok) throw const FormatException('Flux compressé invalide');
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

class _TarSession implements ArchiveSession {
  _TarSession(this.input, this.files, this.entries, this.temp);
  final InputFileStream input;
  final Map<String, ArchiveFile> files;
  final List<ArchiveEntry> entries;
  final File? temp;
  @override
  ArchiveCapabilities get capabilities => const ArchiveCapabilities();
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final file = files[entry.path];
    if (file == null) throw const ArchiveFailure('Entrée absente');
    final bytes = file.readBytes();
    if (bytes == null) throw const ArchiveFailure('Entrée illisible');
    return _BytesSource(entry.name, bytes);
  }

  @override
  Future<void> close() async {
    input.closeSync();
    if (temp != null && temp!.existsSync()) temp!.deleteSync();
  }
}

class _SingleFileSession implements ArchiveSession {
  _SingleFileSession(this.entry, this.file);
  final ArchiveEntry entry;
  final File file;
  @override
  ArchiveCapabilities get capabilities => const ArchiveCapabilities();
  @override
  Future<List<ArchiveEntry>> listEntries() async => [entry];
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async =>
      _FileSource(entry.name, file);
  @override
  Future<void> close() async {
    if (file.existsSync()) file.deleteSync();
  }
}

class _BytesSource implements ContentSource {
  _BytesSource(this.displayName, this.bytes);
  @override
  final String displayName;
  final List<int> bytes;
  @override
  String get id => 'tar:$displayName';
  @override
  Future<int?> get length async => bytes.length;
  @override
  Future<Stream<List<int>>> openRead() async => Stream.value(bytes);
}

/// Streams the decompressed file in chunks instead of loading it.
class _FileSource implements MaterializedContentSource {
  _FileSource(this.displayName, this.file);
  @override
  final String displayName;
  final File file;
  @override
  String get id => file.uri.toString();
  @override
  Future<int?> get length => file.length();
  @override
  Future<Stream<List<int>>> openRead() async => file.openRead();
  @override
  Future<File> materialize() async => file;
}
