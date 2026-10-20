import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/archives/archive_safety_policy.dart';
import 'package:nexa_file/core/comics/comic_page_source.dart';
import 'package:nexa_file/core/database/models.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';

void main() {
  test('natural sorting', () {
    final n = ['10.jpg', '1.jpg', '2.jpg']..sort(naturalCompare);
    expect(n, ['1.jpg', '2.jpg', '10.jpg']);
  });
  test('magic wins over extension', () {
    expect(
      FormatDetector()
          .detect(prefix: [0x25, 0x50, 0x44, 0x46, 0x2d], fileName: 'fake.cbz')
          .content,
      ContentKind.pdf,
    );
  });
  test('ZIP image structure detects comic', () {
    final r = FormatDetector().detect(
      prefix: [0x50, 0x4b, 0x03, 0x04],
      fileName: 'book.zip',
      archiveEntries: ['1.jpg', '2.png', '3.webp', '4.jpg', '5.jpg'],
    );
    expect(r.content, ContentKind.comic);
    expect(r.container, ContainerFormat.zip);
  });
  test('safety rejects traversal', () {
    expect(
      () => const ArchiveSafetyPolicy().validate([
        (path: '../x', compressedSize: 1, uncompressedSize: 1),
      ]),
      throwsException,
    );
  });
  test('locator round trip', () {
    final value = ReadingLocator.decode(
      const EpubLocator('epubcfi(/6/2)', 8).encode(),
    );
    expect(value, isA<EpubLocator>());
    expect((value as EpubLocator).chapter, 8);
  });
}
