import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/archives/archive_core.dart';
import 'package:nexa_file/core/archives/archive_safety_policy.dart';
import 'package:nexa_file/core/comics/comic_heuristic.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';

ArchiveEntry entry(String path, {int compressed = 10, int expanded = 100}) =>
    ArchiveEntry(
      path: path,
      compressedSize: compressed,
      uncompressedSize: expanded,
      isDirectory: false,
    );

void main() {
  group('comic detection', () {
    test('CBZ extension is a comic before listing', () {
      final result = FormatDetector().detect(
        prefix: [0x50, 0x4b, 0x03, 0x04],
        fileName: 'album.cbz',
      );
      expect(result.content, ContentKind.comic);
    });

    test('ordinary ZIP requires five images and 70 percent ratio', () {
      const heuristic = ComicHeuristic();
      expect(
        heuristic.isComic([
          entry('1.jpg'),
          entry('2.jpg'),
          entry('3.jpg'),
          entry('4.jpg'),
        ]),
        isFalse,
      );
      expect(
        heuristic.isComic([
          entry('1.jpg'),
          entry('2.jpg'),
          entry('3.png'),
          entry('4.webp'),
          entry('5.jpg'),
          entry('notes.txt'),
        ]),
        isTrue,
      );
    });

    test('metadata and hidden files do not dilute the ratio', () {
      const heuristic = ComicHeuristic();
      expect(
        heuristic.isComic([
          entry('001.jpg'),
          entry('002.jpg'),
          entry('003.jpg'),
          entry('004.jpg'),
          entry('005.jpg'),
          entry('ComicInfo.xml'),
          entry('__MACOSX/._001.jpg'),
          entry('.hidden'),
        ]),
        isTrue,
      );
    });
  });

  group('archive safety', () {
    test('rejects absolute and parent traversal paths', () {
      const policy = ArchiveSafetyPolicy();
      expect(
        () => policy.validate([
          (path: '/etc/passwd', compressedSize: 1, uncompressedSize: 1),
        ]),
        throwsException,
      );
      expect(
        () => policy.validate([
          (path: 'a/../secret', compressedSize: 1, uncompressedSize: 1),
        ]),
        throwsException,
      );
    });

    test('rejects dangerous expansion ratio', () {
      expect(
        () => const ArchiveSafetyPolicy(maxCompressionRatio: 10).validate([
          (path: 'page.jpg', compressedSize: 10, uncompressedSize: 101),
        ]),
        throwsException,
      );
    });

    test('accepts a bounded archive', () {
      expect(
        () => const ArchiveSafetyPolicy().validate([
          (path: 'chapter/001.jpg', compressedSize: 50, uncompressedSize: 100),
        ]),
        returnsNormally,
      );
    });
  });
}
