import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/database/models.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/readers/epub_adapter.dart';
import 'package:nexa_file/core/readers/epub_package.dart';
import 'package:nexa_file/core/storage/local_storage_repository.dart';
import 'package:nexa_file/features/reader/epub_reader_screen.dart';

const _container =
    '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/>'
    '</rootfiles></container>';

String _opf({bool epub3 = true}) =>
    '<package xmlns="http://www.idpf.org/2007/opf" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>'
    '<dc:title>Le Livre</dc:title><dc:creator>Ada</dc:creator>'
    '${epub3 ? '' : '<meta name="cover" content="img"/>'}'
    '</metadata><manifest>'
    '<item id="c1" href="text/ch%201.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="notes" href="text/notes.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="img" href="images/cover.jpg" media-type="image/jpeg"'
    '${epub3 ? ' properties="cover-image"' : ''}/>'
    '${epub3 ? '<item id="nav" href="nav.xhtml" properties="nav"/>' : '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'}'
    '</manifest><spine>'
    '<itemref idref="c1"/><itemref idref="c2"/>'
    '<itemref idref="notes" linear="no"/><itemref idref="c1"/>'
    '</spine></package>';

const _nav =
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol>'
    '<li><a href="text/ch%201.xhtml#top">  Premier\n chapitre </a></li>'
    '</ol></nav></body></html>';
const _ncx =
    '<ncx><navMap><navPoint><navLabel><text>Le début</text></navLabel>'
    '<content src="text/ch2.xhtml"/></navPoint></navMap></ncx>';

String? Function(String) _reader(Map<String, String> files) =>
    (path) => files[path];

Uint8List _epub() {
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(_container),
    'OEBPS/content.opf': utf8.encode(_opf()),
    'OEBPS/nav.xhtml': utf8.encode(_nav),
    'OEBPS/text/ch 1.xhtml': utf8.encode(
      '<html><head><style>p{}</style></head><body><p>Il était une fois.</p>'
      '<script>bad()</script></body></html>',
    ),
    'OEBPS/text/ch2.xhtml': utf8.encode(
      '<html><body><p>${'blabla ' * 20}la baleine blanche</p></body></html>',
    ),
    'OEBPS/text/notes.xhtml': utf8.encode('<p>notes</p>'),
    'OEBPS/images/cover.jpg': [0xff, 0xd8, 0xff],
  };
  final archive = Archive();
  files.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('package parsing', () {
    test('root file comes from container.xml', () {
      expect(epubRootFile(_container), 'OEBPS/content.opf');
    });

    test('EPUB 3: spine, nav titles, cover-image, skips non-linear', () {
      final package = parseEpubPackage(
        'OEBPS/content.opf',
        _opf(),
        _reader({'OEBPS/nav.xhtml': _nav}),
      );
      expect(package.title, 'Le Livre');
      expect(package.author, 'Ada');
      expect(package.coverHref, 'OEBPS/images/cover.jpg');
      expect(package.chapters.map((c) => c.href), [
        'OEBPS/text/ch 1.xhtml',
        'OEBPS/text/ch2.xhtml',
      ]);
      expect(package.chapters.map((c) => c.title), [
        'Premier chapitre',
        'Chapitre 2',
      ]);
    });

    test('EPUB 2: NCX titles and <meta name="cover">', () {
      final package = parseEpubPackage(
        'OEBPS/content.opf',
        _opf(epub3: false),
        _reader({'OEBPS/toc.ncx': _ncx}),
      );
      expect(package.coverHref, 'OEBPS/images/cover.jpg');
      expect(package.chapters[1].title, 'Le début');
    });

    test('a broken table of contents keeps the book readable', () {
      final package = parseEpubPackage(
        'OEBPS/content.opf',
        _opf(),
        _reader({'OEBPS/nav.xhtml': '<nav><a href="x">'}),
      );
      expect(package.chapters.length, 2);
    });

    test('plain text drops markup, styles and scripts', () {
      expect(
        epubPlainText(
          '<head><title>T</title></head><style>x{}</style>'
          '<p>A &amp; B</p><script>evil()</script><p>C</p>',
        ),
        'A & B C',
      );
    });
  });

  group('reader adapter', () {
    late Directory temp;
    final storage = LocalStorageRepository();
    setUp(() {
      temp = Directory.systemTemp.createTempSync('nexa_lot7_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    Future<File> book() async =>
        File('${temp.path}/livre.epub')..writeAsBytesSync(_epub());

    test('extracts once, then reopens from the cache', () async {
      final file = await book();
      const format = DetectedFormat(
        container: ContainerFormat.zip,
        content: ContentKind.epub,
        confidence: 1,
      );
      final entry = (await storage.get(file.uri))!;
      final first =
          await const EpubReaderAdapter().open(storage.sourceFor(entry), format)
              as EpubReaderSession;
      expect(first.title, 'Le Livre');
      expect(first.chapters.first.title, 'Premier chapitre');
      expect(first.coverBytes, [0xff, 0xd8, 0xff]);
      expect(File(first.chapterPath(0)).existsSync(), isTrue);

      // Tamper with the extraction: a reopen must reuse it, not re-extract.
      File(first.chapterPath(0)).writeAsStringSync('<p>cached</p>');
      final second =
          await const EpubReaderAdapter().open(storage.sourceFor(entry), format)
              as EpubReaderSession;
      expect(second.rootPath, first.rootPath);
      expect(await second.chapterText(0), 'cached');
    });

    test('search returns chapter and position, wrapping around', () async {
      final file = await book();
      final session =
          await const EpubReaderAdapter().open(
                storage.sourceFor((await storage.get(file.uri))!),
                const DetectedFormat(
                  container: ContainerFormat.zip,
                  content: ContentKind.epub,
                  confidence: 1,
                ),
              )
              as EpubReaderSession;
      final hit = (await session.search('BALEINE', fromChapter: 1))!;
      expect(hit.chapter, 1);
      expect(hit.fraction, greaterThan(.8));
      expect((await session.search('une fois', fromChapter: 1))!.chapter, 0);
      expect(await session.search('absent'), isNull);
    });

    test('metadata is read without extracting the book', () async {
      final meta = await EpubReaderAdapter.readMetadata(await book());
      expect(meta.title, 'Le Livre');
      expect(meta.author, 'Ada');
      expect(meta.coverBytes, [0xff, 0xd8, 0xff]);
      expect(Directory('${temp.path}/nexa_cache').existsSync(), isFalse);
    });

    test('cache key is stable and content-sensitive', () {
      expect(stableHash('a|1|2'), stableHash('a|1|2'));
      expect(stableHash('a|1|2'), isNot(stableHash('a|1|3')));
    });
  });

  group('reading position', () {
    test('locator keeps the position inside the chapter', () {
      final decoded =
          ReadingLocator.decode(const EpubLocator('href:a', 3, .5).encode())
              as EpubLocator;
      expect(decoded.chapter, 3);
      expect(decoded.progress, .5);
    });

    test('older saves without position still decode', () {
      final decoded =
          ReadingLocator.decode('{"type":"epub","cfi":"href:a","chapter":2}')
              as EpubLocator;
      expect(decoded.chapter, 2);
      expect(decoded.progress, isNull);
    });

    test('book progress combines chapter and page', () {
      expect(
        epubBookProgress(chapter: 0, chapterCount: 4, page: 1, pageCount: 2),
        .25,
      );
      expect(
        epubBookProgress(chapter: 3, chapterCount: 4, page: 9, pageCount: 10),
        1,
      );
    });

    test('tap zones', () {
      expect(epubTapDirection(50, 1000), -1);
      expect(epubTapDirection(500, 1000), 0);
      expect(epubTapDirection(950, 1000), 1);
    });
  });
}
