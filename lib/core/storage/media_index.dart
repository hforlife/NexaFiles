import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'mime_types.dart';
import 'storage_entry.dart';

/// Search filters over the whole storage.
class SearchFilters {
  const SearchFilters({
    this.categories = const {},
    this.minSize,
    this.modifiedAfter,
    this.modifiedBefore,
    this.under,
    this.sort = SearchSort.date,
    this.folders = true,
  });

  /// Keys of the home categories ("images", "documents"…) plus "folders".
  final Set<String> categories;
  final int? minSize;
  final DateTime? modifiedAfter, modifiedBefore;

  /// Only files below this folder path.
  final String? under;
  final SearchSort sort;
  final bool folders;

  bool get isEmpty =>
      categories.isEmpty &&
      minSize == null &&
      modifiedAfter == null &&
      modifiedBefore == null;
}

enum SearchSort { date, size, name }

/// Identical files (same size and content).
class DuplicateGroup {
  const DuplicateGroup(this.size, this.files, {required this.certain});
  final int size;

  /// Oldest first: the first one is the natural copy to keep.
  final List<StorageEntry> files;

  /// False for very large files compared on their first and last bytes only.
  final bool certain;
  int get wasted => size * (files.length - 1);
}

enum ApkState { installed, update, notInstalled, invalid }

class ApkInfo {
  const ApkInfo(this.entry, this.state, {this.label, this.version});
  final StorageEntry entry;
  final ApkState state;
  final String? label, version;
}

/// Android's media index (MediaStore): instant search and storage analysis
/// without walking the file system.
class MediaIndex {
  const MediaIndex();
  static const _channel = MethodChannel('nexa_file/storage');

  Future<List<StorageEntry>> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    int limit = 500,
  }) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('search', {
          'query': query,
          'categories': filters.categories.toList(),
          'minSize': filters.minSize,
          'modifiedAfter': filters.modifiedAfter?.millisecondsSinceEpoch,
          'modifiedBefore': filters.modifiedBefore?.millisecondsSinceEpoch,
          'under': filters.under,
          'folders': filters.folders,
          'sort': filters.sort.name,
          'limit': limit,
        }) ??
        const [];
    return [for (final row in rows) _entry(row)];
  }

  Future<List<DuplicateGroup>> duplicates({int minSize = 100 * 1024}) async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('duplicates', {
          'minSize': minSize,
        }) ??
        const [];
    return [
      for (final row in rows)
        DuplicateGroup((row['size']! as num).toInt(), [
          for (final path in (row['paths']! as List).cast<String>())
            _fileEntry(path, (row['size']! as num).toInt()),
        ], certain: row['certain'] == true),
    ];
  }

  Future<List<ApkInfo>> apkStatus(List<StorageEntry> apks) async {
    if (apks.isEmpty) return const [];
    final byPath = {for (final e in apks) e.uri.toFilePath(): e};
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('apkStatus', {
          'paths': byPath.keys.toList(),
        }) ??
        const [];
    return [
      for (final row in rows)
        if (byPath[row['path']] case final entry?)
          ApkInfo(
            entry,
            ApkState.values.asNameMap()[row['status']] ?? ApkState.invalid,
            label: row['label'] as String?,
            version: row['version'] as String?,
          ),
    ];
  }

  static StorageEntry _entry(Map<Object?, Object?> row) {
    final path = row['path']! as String;
    final directory = row['directory'] == true;
    return StorageEntry(
      uri: Uri.file(path),
      displayName: p.basename(path),
      kind: directory ? StorageEntryKind.directory : StorageEntryKind.file,
      mimeType: directory ? null : mimeTypeFor(path),
      size: directory ? null : (row['size'] as num?)?.toInt(),
      modifiedAt: row['modified'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (row['modified']! as num).toInt(),
            ),
    );
  }

  static StorageEntry _fileEntry(String path, int size) => StorageEntry(
    uri: Uri.file(path),
    displayName: p.basename(path),
    kind: StorageEntryKind.file,
    mimeType: mimeTypeFor(path),
    size: size,
  );
}
