import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';

void main() {
  const zip = <int>[0x50, 0x4b, 0x03, 0x04];
  test('DOCX structure is not exposed as an archive', () {
    final result = FormatDetector().detect(
        prefix: zip,
        fileName: 'report.docx',
        archiveEntries: const ['[Content_Types].xml', 'word/document.xml']);
    expect(result.content, ContentKind.officeWord);
  });
  test('XLSX structure is not exposed as an archive', () {
    final result = FormatDetector().detect(
        prefix: zip,
        fileName: 'table.xlsx',
        archiveEntries: const ['[Content_Types].xml', 'xl/workbook.xml']);
    expect(result.content, ContentKind.officeSpreadsheet);
  });
  test('PPTX structure is not exposed as an archive', () {
    final result = FormatDetector().detect(
        prefix: zip,
        fileName: 'slides.pptx',
        archiveEntries: const ['[Content_Types].xml', 'ppt/presentation.xml']);
    expect(result.content, ContentKind.officePresentation);
  });
  test('EPUB and CBZ keep precedence rules', () {
    expect(
        FormatDetector().detect(
            prefix: zip,
            fileName: 'book.epub',
            archiveEntries: const [
              'mimetype',
              'META-INF/container.xml'
            ]).content,
        ContentKind.epub);
    expect(
        FormatDetector().detect(
            prefix: zip,
            fileName: 'comic.cbz',
            archiveEntries: const ['1.jpg']).content,
        ContentKind.comic);
  });
}
