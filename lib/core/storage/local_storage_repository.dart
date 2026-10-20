import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../errors/app_failure.dart';
import 'content_source.dart';
import 'mime_types.dart';
import 'storage_entry.dart';
import 'storage_repository.dart';

/// Shared storage accessed directly with dart:io ("all files access").
/// Entries are identified by `file://` URIs.
class LocalStorageRepository implements StorageRepository {
  static const _channel = MethodChannel('nexa_file/storage');

  @override
  Future<bool> hasAllFilesAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestAllFilesAccess() =>
      _channel.invokeMethod<void>('requestAllFilesAccess');

  @override
  Future<List<StorageVolume>> volumes() async =>
      ((await _channel.invokeListMethod<Object?>('volumes')) ?? const [])
          .cast<Map<Object?, Object?>>()
          .map(
            (e) => StorageVolume(
              path: e['path']! as String,
              name: e['name']! as String,
              primary: e['primary'] == true,
              removable: e['removable'] == true,
              totalBytes: e['total'] as int?,
              freeBytes: e['free'] as int?,
            ),
          )
          .toList();

  @override
  Future<Map<String, CategoryStats>> categoryStats() async {
    final rows =
        await _channel.invokeMapMethod<String, Object?>('categoryStats') ??
        const {};
    return {
      for (final MapEntry(:key, :value) in rows.entries)
        key: CategoryStats(
          ((value as Map)['count'] as num).toInt(),
          (value['bytes'] as num).toInt(),
        ),
    };
  }

  @override
  Future<List<StorageEntry>> categoryFiles(
    String category, {
    int limit = 2000,
  }) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>(
          'categoryFiles',
          {'category': category, 'limit': limit},
        ) ??
        const [];
    return [
      for (final row in rows)
        StorageEntry(
          uri: Uri.file(row['path']! as String),
          displayName: p.basename(row['path']! as String),
          kind: StorageEntryKind.file,
          mimeType: mimeTypeFor(row['path']! as String),
          size: (row['size'] as num?)?.toInt(),
          modifiedAt: row['modified'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (row['modified']! as num).toInt(),
                ),
        ),
    ];
  }

  @override
  Future<List<StorageEntry>> list(Uri directoryUri) {
    final path = directoryUri.toFilePath();
    // Stat calls run off the UI isolate so large folders never cause jank.
    return _guard(() => Isolate.run(() => _listSync(path)));
  }

  @override
  Future<StorageEntry?> get(Uri uri) =>
      _guard(() async => _entryFor(uri.toFilePath()));

  @override
  Future<StorageEntry> createDirectory(Uri parentUri, String name) =>
      _guard(() async {
        final target = _freeTarget(parentUri.toFilePath(), name);
        await Directory(target).create();
        return _entryFor(target)!;
      });

  @override
  Future<StorageEntry> createFile(
    Uri parentUri,
    String name,
    Uint8List bytes,
  ) => _guard(() async {
    final target = _freeTarget(parentUri.toFilePath(), name);
    await File(target).writeAsBytes(bytes, flush: true);
    _scan([target]);
    return _entryFor(target)!;
  });

  @override
  Future<StorageEntry> rename(Uri uri, String name) => _guard(() async {
    final source = uri.toFilePath();
    final target = _freeTarget(p.dirname(source), name);
    await _entity(source).rename(target);
    _scan([source, target]);
    return _entryFor(target)!;
  });

  @override
  Future<StorageEntry> copy(
    Uri sourceUri,
    Uri targetDirectoryUri, {
    String? targetName,
  }) => _guard(() async {
    final source = sourceUri.toFilePath();
    final target = _freeTarget(
      targetDirectoryUri.toFilePath(),
      targetName ?? p.basename(source),
    );
    await _copyTree(source, target);
    _scan([target]);
    return _entryFor(target)!;
  });

  @override
  Future<StorageEntry> move(
    Uri sourceUri,
    Uri targetDirectoryUri, {
    String? targetName,
  }) => _guard(() async {
    final source = sourceUri.toFilePath();
    final target = _freeTarget(
      targetDirectoryUri.toFilePath(),
      targetName ?? p.basename(source),
    );
    try {
      await _entity(source).rename(target);
    } on FileSystemException catch (e) {
      // EXDEV: rename cannot cross volumes, fall back to copy + delete.
      if (e.osError?.errorCode != 18) rethrow;
      await _copyTree(source, target);
      await _entity(source).delete(recursive: true);
    }
    _scan([source, target]);
    return _entryFor(target)!;
  });

  @override
  Future<void> delete(Uri uri) => _guard(() async {
    final path = uri.toFilePath();
    await _entity(path).delete(recursive: true);
    _scan([path]);
  });

  @override
  Future<void> share(List<Uri> uris, {String? mimeType}) => _guard(
    () => _channel.invokeMethod<void>('share', {
      'paths': [for (final uri in uris) uri.toFilePath()],
      'mime': mimeType ?? '*/*',
    }),
  );

  @override
  Future<void> openExternal(Uri uri, {String? mimeType}) => _guard(
    () => _channel.invokeMethod<void>('openWith', {
      'path': uri.toFilePath(),
      'mime': mimeType,
    }),
  );

  @override
  Future<Uint8List> readPrefix(Uri uri, {int length = 32}) => _guard(() async {
    final file = await File(uri.toFilePath()).open();
    try {
      return await file.read(length);
    } finally {
      await file.close();
    }
  });

  @override
  ContentSource sourceFor(StorageEntry entry) =>
      _LocalContentSource(File(entry.uri.toFilePath()), entry.displayName);

  /// Keeps the Android media index (gallery, music apps) in sync. Best effort.
  void _scan(List<String> paths) {
    unawaited(
      _channel.invokeMethod<void>('scan', {'paths': paths}).catchError((_) {}),
    );
  }
}

class _LocalContentSource implements MaterializedContentSource {
  _LocalContentSource(this.file, this.displayName);
  final File file;
  @override
  final String displayName;
  @override
  String get id => '${file.uri}';
  @override
  Future<int?> get length => file.length();
  @override
  Future<Stream<List<int>>> openRead() async => file.openRead();

  /// Already a real file: readers and archive tools use it in place, no copy.
  @override
  Future<File> materialize() async => file;
}

Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on FileSystemException catch (e) {
    final code = e.osError?.errorCode;
    if (code == 13 || code == 1) {
      throw PermissionFailure('Accès refusé : ${e.path ?? ''}', e);
    }
    if (code == 28) {
      throw InsufficientSpaceFailure('Espace de stockage insuffisant', e);
    }
    throw StorageFailure(e.osError?.message ?? e.message, e);
  } on PlatformException catch (e) {
    throw StorageFailure(e.message ?? 'Erreur de stockage', e);
  }
}

List<StorageEntry> _listSync(String path) => [
  for (final child in Directory(path).listSync(followLinks: false))
    ?_entryFor(child.path),
];

StorageEntry? _entryFor(String path) {
  final stat = FileStat.statSync(path); // follows symlinks
  if (stat.type == FileSystemEntityType.notFound) return null;
  final name = p.basename(path);
  final directory = stat.type == FileSystemEntityType.directory;
  return StorageEntry(
    uri: Uri.file(path),
    displayName: name,
    kind: directory ? StorageEntryKind.directory : StorageEntryKind.file,
    mimeType: directory ? null : mimeTypeFor(name),
    size: directory ? null : stat.size,
    modifiedAt: stat.modified,
  );
}

FileSystemEntity _entity(String path) =>
    FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);

/// Target path for a new entry; refuses to overwrite an existing one.
String _freeTarget(String directory, String name) {
  final target = p.join(directory, name);
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const StorageFailure('Un élément porte déjà ce nom.');
  }
  return target;
}

Future<void> _copyTree(String source, String target) async {
  if (!FileSystemEntity.isDirectorySync(source)) {
    await File(source).copy(target);
    return;
  }
  await Directory(target).create();
  await for (final child in Directory(source).list(followLinks: false)) {
    await _copyTree(child.path, p.join(target, p.basename(child.path)));
  }
}
