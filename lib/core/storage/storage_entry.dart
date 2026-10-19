enum StorageEntryKind { file, directory }

class StorageCapabilities {
  const StorageCapabilities(
      {this.canRead = true,
      this.canWrite = false,
      this.canDelete = false,
      this.canRename = false});
  final bool canRead, canWrite, canDelete, canRename;
}

class StorageEntry {
  const StorageEntry(
      {required this.uri,
      required this.displayName,
      required this.kind,
      this.mimeType,
      this.size,
      this.modifiedAt,
      this.capabilities = const StorageCapabilities()});
  final Uri uri;
  final String displayName;
  final StorageEntryKind kind;
  final String? mimeType;
  final int? size;
  final DateTime? modifiedAt;
  final StorageCapabilities capabilities;
  factory StorageEntry.fromPlatform(Map<Object?, Object?> map) => StorageEntry(
      uri: Uri.parse(map['uri']! as String),
      displayName: (map['name'] as String?) ?? 'Sans nom',
      kind: map['directory'] == true
          ? StorageEntryKind.directory
          : StorageEntryKind.file,
      mimeType: map['mime'] as String?,
      size: map['size'] as int?,
      modifiedAt: (map['modified'] as int? ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(map['modified']! as int)
          : null,
      capabilities: StorageCapabilities(
          canRead: map['read'] == true,
          canWrite: map['write'] == true,
          canDelete: map['write'] == true,
          canRename: map['write'] == true));
}
