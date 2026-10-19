import 'dart:typed_data';
import 'content_source.dart';
import 'storage_entry.dart';

abstract interface class StorageRepository {
  Future<StorageEntry?> pickDirectory();
  Future<List<StorageEntry>> grantedRoots();
  Future<void> releaseRoot(Uri uri);
  Future<List<StorageEntry>> list(Uri directoryUri);
  Future<StorageEntry?> get(Uri uri);
  Future<StorageEntry> createDirectory(Uri parentUri, String name);
  Future<StorageEntry> createFile(Uri parentUri, String name, Uint8List bytes,
      {String mimeType});
  Future<StorageEntry> rename(Uri uri, String name);
  Future<StorageEntry> copy(Uri sourceUri, Uri targetDirectoryUri,
      {String? targetName});
  Future<StorageEntry> move(Uri sourceUri, Uri targetDirectoryUri,
      {String? targetName});
  Future<void> delete(Uri uri);
  Future<void> share(List<Uri> uris, {String? mimeType});
  Future<void> openExternal(Uri uri, {String? mimeType});

  /// Reads only the bytes required for format sniffing. It must never materialize
  /// the complete document merely to classify it.
  Future<Uint8List> readPrefix(Uri uri, {int length = 32});
  ContentSource sourceFor(StorageEntry entry);
}
