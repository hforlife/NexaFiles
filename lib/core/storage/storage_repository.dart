import 'dart:typed_data';
import 'content_source.dart';
import 'storage_entry.dart';

/// A mounted storage volume (internal storage, SD card…).
class StorageVolume {
  const StorageVolume({
    required this.path,
    required this.name,
    required this.primary,
    required this.removable,
    this.totalBytes,
    this.freeBytes,
  });
  final String path, name;
  final bool primary, removable;
  final int? totalBytes, freeBytes;
}

/// Number and total size of the files of a home-screen category.
class CategoryStats {
  const CategoryStats(this.count, this.bytes);
  final int count, bytes;
}

/// Home-screen categories, as indexed by the system media store.
const fileCategoryKeys = [
  'images',
  'videos',
  'audio',
  'documents',
  'books',
  'archives',
  'apps',
];

abstract interface class StorageRepository {
  /// Whether the app may read and write shared storage ("all files access").
  Future<bool> hasAllFilesAccess();

  /// Opens the system permission screen; callers re-check on resume.
  Future<void> requestAllFilesAccess();
  Future<List<StorageVolume>> volumes();

  /// Per-category totals over all volumes (keys from [fileCategoryKeys]).
  Future<Map<String, CategoryStats>> categoryStats();

  /// Files of a category, most recently modified first.
  Future<List<StorageEntry>> categoryFiles(String category, {int limit = 2000});
  Future<List<StorageEntry>> list(Uri directoryUri);
  Future<StorageEntry?> get(Uri uri);
  Future<StorageEntry> createDirectory(Uri parentUri, String name);
  Future<StorageEntry> createFile(Uri parentUri, String name, Uint8List bytes);
  Future<StorageEntry> rename(Uri uri, String name);
  Future<StorageEntry> copy(
    Uri sourceUri,
    Uri targetDirectoryUri, {
    String? targetName,
  });

  /// Moves a file or a folder; instant on the same volume.
  Future<StorageEntry> move(
    Uri sourceUri,
    Uri targetDirectoryUri, {
    String? targetName,
  });
  Future<void> delete(Uri uri);
  Future<void> share(List<Uri> uris, {String? mimeType});
  Future<void> openExternal(Uri uri, {String? mimeType});

  /// Reads only the bytes required for format sniffing. It must never materialize
  /// the complete document merely to classify it.
  Future<Uint8List> readPrefix(Uri uri, {int length = 32});
  ContentSource sourceFor(StorageEntry entry);
}
