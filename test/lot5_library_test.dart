import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/library/library_repository.dart';
import 'package:nexa_file/core/library/library_scanner.dart';

LibraryRecord item({double? progress, String? status}) => LibraryRecord(
  id: 'content://book',
  uri: 'content://book',
  name: 'my_book.epub',
  format: 'epub',
  addedAt: DateTime(2026),
  favorite: false,
  unavailable: false,
  fraction: progress,
  manualStatus: status,
);
void main() {
  test('fallback title removes extension and separators', () {
    expect(fallbackTitle('the_long-book.epub'), 'the long book');
  });
  test('reading status is derived with 95 percent completion threshold', () {
    expect(readingState(item()), ReadingState.notStarted);
    expect(readingState(item(progress: .4)), ReadingState.inProgress);
    expect(readingState(item(progress: .95)), ReadingState.finished);
  });
  test('manual reading status overrides derived progress', () {
    expect(
      readingState(item(progress: .2, status: 'finished')),
      ReadingState.finished,
    );
    expect(
      readingState(item(progress: .9, status: 'unread')),
      ReadingState.notStarted,
    );
  });
  test('scanner recognizes only supported library types', () {
    expect(indexableKind('novel.epub'), ContentKind.epub);
    expect(indexableKind('volume.CBR'), ContentKind.comic);
    expect(indexableKind('photo.jpg'), isNull);
  });
  test('stable identity is the source URI', () {
    final values = {item().uri, item().uri};
    expect(values.length, 1);
  });
}
