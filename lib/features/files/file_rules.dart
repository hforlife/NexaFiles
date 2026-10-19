import '../../core/comics/comic_page_source.dart';
import '../../core/storage/storage_entry.dart';

enum FileSort { name, date, size, type }

enum SortDirection { ascending, descending }

enum ConflictPolicy { replace, keepBoth, skip, cancel }

String? validateEntryName(String value) {
  final name = value.trim();
  if (name.isEmpty) return 'Le nom ne peut pas être vide.';
  if (name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains('\u0000')) {
    return 'Ce nom contient des caractères non autorisés.';
  }
  if (name.length > 255) return 'Ce nom est trop long.';
  return null;
}

String keepBothName(String original, Set<String> existing) {
  if (!existing.contains(original.toLowerCase())) return original;
  final dot = original.lastIndexOf('.'), hasExtension = dot > 0;
  final base = hasExtension ? original.substring(0, dot) : original,
      ext = hasExtension ? original.substring(dot) : '';
  var i = 1;
  while (existing.contains('$base ($i)$ext'.toLowerCase())) {
    i++;
  }
  return '$base ($i)$ext';
}

List<StorageEntry> sortEntries(
    Iterable<StorageEntry> values, FileSort sort, SortDirection direction) {
  final list = values.toList();
  int compare(StorageEntry a, StorageEntry b) {
    if (a.kind != b.kind) return a.kind == StorageEntryKind.directory ? -1 : 1;
    int value;
    switch (sort) {
      case FileSort.name:
        value = naturalCompare(a.displayName, b.displayName);
        break;
      case FileSort.date:
        value = (a.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        break;
      case FileSort.size:
        value = (a.size ?? -1).compareTo(b.size ?? -1);
        break;
      case FileSort.type:
        value = (a.mimeType ?? '').compareTo(b.mimeType ?? '');
        break;
    }
    return direction == SortDirection.ascending ? value : -value;
  }

  list.sort(compare);
  return list;
}
