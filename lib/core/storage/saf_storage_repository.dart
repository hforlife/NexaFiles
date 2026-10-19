import 'dart:io';
import 'package:flutter/services.dart';
import '../errors/app_failure.dart';
import 'content_source.dart';
import 'storage_entry.dart';
import 'storage_repository.dart';

class SafStorageRepository implements StorageRepository {
  static const _channel = MethodChannel('nexa_file/storage');
  @override
  Future<StorageEntry?> pickDirectory() async {
    final uri = await _invoke<String>('pickTree');
    return uri == null ? null : get(Uri.parse(uri));
  }

  @override
  Future<List<StorageEntry>> grantedRoots() async {
    final rows = await _channel.invokeListMethod<Object?>('persisted') ?? [];
    final result = <StorageEntry>[];
    for (final row in rows.cast<Map<Object?, Object?>>()) {
      try {
        final item = await get(Uri.parse(row['uri']! as String));
        if (item != null) result.add(item);
      } catch (_) {/* Keep other valid grants available. */}
    }
    return result;
  }

  @override
  Future<void> releaseRoot(Uri uri) =>
      _invoke<void>('releaseTree', {'uri': '$uri'});
  @override
  Future<List<StorageEntry>> list(Uri uri) async =>
      ((await _channel.invokeListMethod<Object?>('list', {'uri': '$uri'})) ??
              [])
          .cast<Map<Object?, Object?>>()
          .map(StorageEntry.fromPlatform)
          .toList();
  @override
  Future<StorageEntry?> get(Uri uri) async {
    final map = await _channel
        .invokeMapMethod<Object?, Object?>('metadata', {'uri': '$uri'});
    return map == null ? null : StorageEntry.fromPlatform(map);
  }

  @override
  Future<StorageEntry> createDirectory(Uri parentUri, String name) async =>
      (await get(Uri.parse((await _invoke<String>(
          'createDirectory', {'uri': '$parentUri', 'name': name}))!)))!;
  @override
  Future<StorageEntry> createFile(Uri parentUri, String name, Uint8List bytes,
          {String mimeType = 'application/octet-stream'}) async =>
      (await get(Uri.parse((await _invoke<String>('createFile', {
        'uri': '$parentUri',
        'name': name,
        'mime': mimeType,
        'bytes': bytes
      }))!)))!;
  @override
  Future<StorageEntry> rename(Uri uri, String name) async =>
      (await get(Uri.parse(
          (await _invoke<String>('rename', {'uri': '$uri', 'name': name}))!)))!;
  @override
  Future<StorageEntry> copy(Uri sourceUri, Uri targetDirectoryUri,
          {String? targetName}) async =>
      (await get(Uri.parse((await _invoke<String>('copy', {
        'sourceUri': '$sourceUri',
        'targetUri': '$targetDirectoryUri',
        'targetName': targetName
      }))!)))!;
  @override
  Future<StorageEntry> move(Uri sourceUri, Uri targetDirectoryUri,
          {String? targetName}) async =>
      (await get(Uri.parse((await _invoke<String>('move', {
        'sourceUri': '$sourceUri',
        'targetUri': '$targetDirectoryUri',
        'targetName': targetName
      }))!)))!;
  @override
  Future<void> delete(Uri uri) => _invoke<void>('delete', {'uri': '$uri'});
  @override
  Future<void> share(List<Uri> uris, {String? mimeType}) => _invoke<void>(
      'share',
      {'uris': uris.map((e) => '$e').toList(), 'mime': mimeType ?? '*/*'});
  @override
  Future<void> openExternal(Uri uri, {String? mimeType}) =>
      _invoke<void>('openWith', {'uri': '$uri', 'mime': mimeType ?? '*/*'});
  @override
  Future<Uint8List> readPrefix(Uri uri, {int length = 32}) async =>
      (await _channel.invokeMethod<Uint8List>(
          'readPrefix', {'uri': '$uri', 'length': length})) ??
      Uint8List(0);
  @override
  ContentSource sourceFor(StorageEntry entry) => _SafContentSource(entry);
  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw e.code == 'PERMISSION'
          ? PermissionFailure(e.message ?? 'Permission refusée', e)
          : StorageFailure(e.message ?? 'Erreur de stockage', e);
    }
  }
}

class _SafContentSource implements ContentSource, MaterializedContentSource {
  _SafContentSource(this.entry);
  final StorageEntry entry;
  @override
  String get id => '${entry.uri}';
  @override
  String get displayName => entry.displayName;
  @override
  Future<int?> get length async => entry.size;
  @override
  Future<Stream<List<int>>> openRead() async {
    final bytes = await SafStorageRepository._channel
        .invokeMethod<Uint8List>('read', {'uri': '${entry.uri}'});
    if (bytes == null) throw const StorageFailure('Lecture impossible');
    return Stream.value(bytes);
  }

  @override
  Future<File> materialize() async {
    const archiveChannel = MethodChannel('nexa_file/archives');
    final path = await archiveChannel
        .invokeMethod<String>('materialize', {'uri': '${entry.uri}'});
    if (path == null) throw const StorageFailure('Matérialisation impossible');
    return File(path);
  }
}
