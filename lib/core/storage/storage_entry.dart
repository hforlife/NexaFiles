enum StorageEntryKind { file, directory }

class StorageEntry {
  const StorageEntry({
    required this.uri,
    required this.displayName,
    required this.kind,
    this.mimeType,
    this.size,
    this.modifiedAt,
  });
  final Uri uri;
  final String displayName;
  final StorageEntryKind kind;
  final String? mimeType;
  final int? size;
  final DateTime? modifiedAt;
}
