import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/database/models.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';

void main() {
  test('PDF locator round trip', () {
    final value =
        ReadingLocator.decode(const PdfLocator(42).encode()) as PdfLocator;
    expect(value.page, 42);
  });
  test('EPUB locator remains stable', () {
    final value = ReadingLocator.decode(
        const EpubLocator('epubcfi(/6/4!/4/2)', 3).encode()) as EpubLocator;
    expect(value.cfi, 'epubcfi(/6/4!/4/2)');
    expect(value.chapter, 3);
  });
  test('EPUB href and legacy locators remain readable', () {
    final href = ReadingLocator.decode(
            const EpubLocator('href:Text/chapter-3.xhtml', 2).encode())
        as EpubLocator;
    expect(href.cfi, 'href:Text/chapter-3.xhtml');
    final legacy =
        ReadingLocator.decode(const EpubLocator('chapter:2', 2).encode())
            as EpubLocator;
    expect(legacy.chapter, 2);
  });
  test('detects markdown independently from text', () {
    expect(
        FormatDetector()
            .detect(prefix: const [], fileName: 'README.md').content,
        ContentKind.markdown);
  });
  test('detects GIF magic', () {
    expect(
        FormatDetector().detect(
            prefix: const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61],
            fileName: 'image.bin').content,
        ContentKind.image);
  });
  test('ZIP is EPUB only with required structure', () {
    final plain = FormatDetector().detect(
        prefix: const [0x50, 0x4b, 0x03, 0x04],
        fileName: 'book.zip',
        archiveEntries: const ['chapter.xhtml']);
    expect(plain.content, ContentKind.archive);
    final epub = FormatDetector().detect(
        prefix: const [0x50, 0x4b, 0x03, 0x04],
        fileName: 'book.epub',
        archiveEntries: const ['mimetype', 'META-INF/container.xml']);
    expect(epub.content, ContentKind.epub);
  });
}
