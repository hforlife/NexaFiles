import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/storage/storage_entry.dart';
import 'package:nexa_file/features/files/file_rules.dart';

StorageEntry entry(String name,
        {bool directory = false, int? size, DateTime? date, String? mime}) =>
    StorageEntry(
        uri: Uri.parse('content://test/$name'),
        displayName: name,
        kind: directory ? StorageEntryKind.directory : StorageEntryKind.file,
        size: size,
        modifiedAt: date,
        mimeType: mime);
void main() {
  test('entry name validation rejects unsafe values', () {
    expect(validateEntryName(''), isNotNull);
    expect(validateEntryName('../x'), isNotNull);
    expect(validateEntryName('good name.pdf'), isNull);
  });
  test('keep both preserves extension', () {
    expect(keepBothName('document.pdf', {'document.pdf', 'document (1).pdf'}),
        'document (2).pdf');
  });
  test('natural sort keeps folders first', () {
    final values = sortEntries([
      entry('page10'),
      entry('page2'),
      entry('folder', directory: true),
      entry('page1')
    ], FileSort.name, SortDirection.ascending);
    expect(values.map((e) => e.displayName),
        ['folder', 'page1', 'page2', 'page10']);
  });
  test('descending still groups folders consistently', () {
    final values = sortEntries([entry('a'), entry('z', directory: true)],
        FileSort.name, SortDirection.descending);
    expect(values.first.kind, StorageEntryKind.directory);
  });
}
