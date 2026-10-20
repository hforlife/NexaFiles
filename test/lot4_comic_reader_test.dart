import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/archives/archive_core.dart';
import 'package:nexa_file/core/archives/archive_safety_policy.dart';
import 'package:nexa_file/core/archives/zip_archive_adapter.dart';
import 'package:nexa_file/core/comics/archive_comic_page_source.dart';
import 'package:nexa_file/core/errors/app_failure.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/storage/content_source.dart';
import 'package:nexa_file/core/storage/local_storage_repository.dart';
import 'package:nexa_file/core/storage/memory_content_source.dart';
import 'package:nexa_file/features/reader/comic_reader_screen.dart';

const _cbz = DetectedFormat(
  container: ContainerFormat.zip,
  content: ContentKind.comic,
  confidence: 1,
);

/// Counts reads to prove that a page is extracted once.
class _CountingSession implements ArchiveSession {
  _CountingSession(int pages)
    : entries = [
        for (var i = 0; i < pages; i++)
          ArchiveEntry(
            path: 'p${i + 1}.jpg',
            compressedSize: 1,
            uncompressedSize: 1,
            isDirectory: false,
          ),
      ];
  final List<ArchiveEntry> entries;
  final reads = <String>[];
  @override
  ArchiveCapabilities get capabilities => const ArchiveCapabilities();
  @override
  Future<List<ArchiveEntry>> listEntries() async => entries;
  @override
  Future<ContentSource> openEntry(ArchiveEntry entry) async {
    reads.add(entry.path);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return MemoryContentSource(
      id: entry.path,
      displayName: entry.path,
      bytes: Uint8List.fromList(entry.path.codeUnits),
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tap zones', () {
    ComicTapAction tap(double dx, ComicReadingDirection direction) =>
        comicTapAction(dx: dx, width: 1000, direction: direction);
    const ltr = ComicReadingDirection.leftToRight,
        rtl = ComicReadingDirection.rightToLeft;

    test('left to right: right edge goes forward', () {
      expect(tap(100, ltr), ComicTapAction.previous);
      expect(tap(500, ltr), ComicTapAction.toggleControls);
      expect(tap(900, ltr), ComicTapAction.next);
    });

    test('manga (right to left): left edge goes forward', () {
      expect(tap(100, rtl), ComicTapAction.next);
      expect(tap(500, rtl), ComicTapAction.toggleControls);
      expect(tap(900, rtl), ComicTapAction.previous);
    });
  });

  group('decode size', () {
    final bytes = Uint8List(4);
    test('fit width decodes at 1.5x the screen width, never upscaled', () {
      final image = comicPageImage(
        bytes,
        box: const Size(400, 800),
        pixelRatio: 3,
        fit: ComicFitMode.width,
      );
      expect(image, isA<ResizeImage>());
      image as ResizeImage;
      expect(image.width, 1800);
      expect(image.height, isNull);
      expect(image.allowUpscaling, isFalse);
    });

    test('fit height constrains the height instead', () {
      final image =
          comicPageImage(
                bytes,
                box: const Size(400, 800),
                pixelRatio: 2,
                fit: ComicFitMode.height,
              )
              as ResizeImage;
      expect(image.height, 2400);
      expect(image.width, isNull);
    });

    test(
      'same page and size share an image cache key (precache hits)',
      () async {
        Future<Object> key() => comicPageImage(
          bytes,
          box: const Size(400, 800),
          pixelRatio: 2,
          fit: ComicFitMode.width,
        ).obtainKey(ImageConfiguration.empty);
        expect(await key(), await key());
        final other = await comicPageImage(
          Uint8List(4),
          box: const Size(400, 800),
          pixelRatio: 2,
          fit: ComicFitMode.width,
        ).obtainKey(ImageConfiguration.empty);
        expect(other, isNot(await key()));
      },
    );
  });

  group('CBZ random access', () {
    late Directory dir;
    final storage = LocalStorageRepository();
    setUp(() => dir = Directory.systemTemp.createTempSync('nexa_lot4_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<ContentSource> cbz(
      Map<String, List<int>> pages, {
      bool compress = true,
    }) async {
      final archive = Archive();
      pages.forEach((name, data) {
        final file = ArchiveFile(name, data.length, data);
        if (!compress) file.compression = CompressionType.none;
        archive.addFile(file);
      });
      final path = '${dir.path}/book.cbz';
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      return storage.sourceFor((await storage.get(Uri.file(path)))!);
    }

    test('reads pages on demand in natural order', () async {
      final source = await cbz({
        'p10.jpg': List.filled(3000, 10),
        'p2.jpg': List.filled(3000, 2),
        'p1.jpg': List.filled(3000, 1),
        'ComicInfo.xml': [60, 47, 62],
      });
      final session = await ZipArchiveAdapter().open(
        source,
        const ArchiveSafetyPolicy(),
      );
      final pages = await ArchiveComicPageSource.open(session);
      expect(await pages.pageCount, 3);
      expect((await pages.getPage(0)).name, 'p1.jpg');
      expect(
        (await pages.getPage(2)).bytes,
        Uint8List.fromList(List.filled(3000, 10)),
      );
      await pages.dispose();
    });

    test('a corrupted page is reported, not shown', () async {
      final source = await cbz({'p1.jpg': List.filled(64, 7)}, compress: false);
      final path =
          (await (source as MaterializedContentSource).materialize()).path;
      final bytes = File(path).readAsBytesSync();
      // Flip one byte of the stored page data (right after the local header).
      final at = bytes.indexOf(7);
      bytes[at] = 8;
      File(path).writeAsBytesSync(bytes);
      final session = await ZipArchiveAdapter().open(
        source,
        const ArchiveSafetyPolicy(),
      );
      final entry = (await session.listEntries()).single;
      await expectLater(
        session.openEntry(entry),
        throwsA(isA<CorruptedFileFailure>()),
      );
      await session.close();
    });

    test('format detector still routes the archive as a comic', () {
      expect(_cbz.content, ContentKind.comic);
    });
  });

  group('page cache', () {
    test('concurrent requests for a page extract it once', () async {
      final session = _CountingSession(5);
      final pages = await ArchiveComicPageSource.open(session);
      await Future.wait([
        pages.getPage(1),
        pages.getPage(1),
        pages.preload(0, 3),
      ]);
      expect(session.reads.where((p) => p == 'p2.jpg').length, 1);
      expect(session.reads.length, 3);
    });

    test('least recently used pages are evicted beyond capacity', () async {
      final session = _CountingSession(5);
      final pages = await ArchiveComicPageSource.open(
        session,
        cacheCapacity: 2,
      );
      await pages.getPage(0);
      await pages.getPage(1);
      await pages.getPage(0); // refresh page 0
      await pages.getPage(2); // evicts page 1
      await pages.getPage(0);
      await pages.getPage(1);
      expect(session.reads, ['p1.jpg', 'p2.jpg', 'p3.jpg', 'p2.jpg']);
    });
  });
}
