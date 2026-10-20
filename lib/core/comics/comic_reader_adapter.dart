import '../archives/archive_core.dart';
import '../formats/detected_format.dart';
import '../readers/reader_core.dart';
import '../storage/content_source.dart';
import 'archive_comic_page_source.dart';
import 'comic_heuristic.dart';
import 'comic_page_source.dart';

class ComicReaderAdapter implements ReaderAdapter {
  ComicReaderAdapter(this.archives);
  final ArchiveRegistry archives;
  @override
  Set<ContentKind> get supportedKinds => const {ContentKind.comic};
  @override
  Future<ReaderSession> open(
    ContentSource source,
    DetectedFormat format,
  ) async {
    final archive = await archives.open(source, format);
    final entries = await archive.listEntries();
    if (!const ComicHeuristic().isComic(entries) &&
        format.content != ContentKind.comic) {
      await archive.close();
      throw StateError('Cette archive ne ressemble pas à une bande dessinée.');
    }
    final pages = await ArchiveComicPageSource.open(archive);
    if (await pages.pageCount == 0) {
      await pages.dispose();
      throw StateError('Aucune image lisible dans cette archive.');
    }
    return ComicReaderSession(source, format, pages);
  }
}

class ComicReaderSession implements ReaderSession {
  ComicReaderSession(this.source, this.format, this.pages);
  @override
  final ContentSource source;
  final DetectedFormat format;
  final ComicPageSource pages;
  @override
  ReaderType get type => ReaderType.comic;
  @override
  Future<void> dispose() => pages.dispose();
}
