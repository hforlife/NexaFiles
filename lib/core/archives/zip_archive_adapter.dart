import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
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
    ArchiveSafetyPolicy safetyPolicy, {
    String? password,
  }) async {
    final file = await _materialize(source);
    final input = InputFileStream(file.path);
    try {
      final directory = ZipDirectory()..read(input, password: password);
      final headers = {
        for (final header in directory.fileHeaders) header.filename: header,
      };
      final entries = [
        for (final header in headers.values)
          ArchiveEntry(
            path: header.filename,
            compressedSize: header.compressedSize,
            uncompressedSize: header.uncompressedSize,
            isDirectory: header.filename.endsWith('/'),
            // Bit 0 of the general purpose flags: entry is encrypted.
            encrypted: ((header.file?.flags ?? 0) & 1) != 0,
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
      return _ZipSession(source, input, headers, entries, password, file.path);
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
  _ZipSession(
    this.source,
    this.input,
    this.headers,
    this.entries,
    this.password,
    this.path,
  );
  final ContentSource source;
  final InputFileStream input;
  final Map<String, ZipFileHeader> headers;
  final List<ArchiveEntry> entries;
  final String? password;

  /// Local archive file, reopened by background isolates.
  final String path;
  @override
  ArchiveCapabilities get capabilities =>
      const ArchiveCapabilities(canCreate: true, canRandomAccess: true);
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    final header = headers[entry.path];
    if (header == null) throw const ArchiveFailure('Entrée absente');
    final encrypted = ((header.file?.flags ?? 0) & 1) != 0;
    if (encrypted && password == null) throw const PasswordRequiredFailure();
    if (encrypted) {
      // AES derives a key (PBKDF2) for every entry: far too slow for the UI
      // thread, so decryption runs in a background isolate.
      // Plain values only: a closure here would capture this session and
      // its open file, which cannot cross isolates.
      final data = await compute(_decryptEntry, (path, entry.path, password!));
      return MemoryContentSource(
        id: '${source.id}#${entry.path}',
        displayName: entry.name,
        bytes: data,
      );
    }
    // ZipFile.getStream() inflates on every call and keeps nothing cached,
    // so pages read earlier do not accumulate in memory.
    final file = header.file;
    if (file == null) throw const ArchiveFailure('Entrée illisible');
    final Uint8List data;
    try {
      data = file.getStream().toUint8List();
    } catch (e) {
      // AES reports a bad password as an exception ("password error").
      if (encrypted) throw const WrongPasswordFailure();
      rethrow;
    }
    if (getCrc32(data) != header.crc32) {
      // ZipCrypto has no check: a wrong password shows as a CRC mismatch.
      throw encrypted
          ? const WrongPasswordFailure()
          : const CorruptedFileFailure();
    }
    return MemoryContentSource(
      id: '${source.id}#${entry.path}',
      displayName: entry.name,
      bytes: data,
    );
  }

  @override
  Future<void> close() async => input.closeSync();
}

/// Reads and decrypts one entry of the ZIP at [path] (isolate entry point).
Uint8List _decryptEntry((String, String, String) args) {
  final (path, name, password) = args;
  final input = InputFileStream(path);
  try {
    final directory = ZipDirectory()..read(input, password: password);
    final header = directory.fileHeaders.firstWhere(
      (h) => h.filename == name,
      orElse: () => throw const ArchiveFailure('Entrée absente'),
    );
    final file = header.file;
    if (file == null) throw const ArchiveFailure('Entrée illisible');
    final Uint8List data;
    try {
      data = file.getStream().toUint8List();
    } catch (_) {
      throw const WrongPasswordFailure();
    }
    // ZipCrypto has no check: a wrong password shows as a CRC mismatch.
    if (getCrc32(data) != header.crc32) throw const WrongPasswordFailure();
    return data;
  } finally {
    input.closeSync();
  }
}
