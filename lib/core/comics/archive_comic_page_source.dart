import 'dart:typed_data';
import '../archives/archive_core.dart';
import '../storage/memory_content_source.dart';
import 'comic_page_source.dart';

class ArchiveComicPageSource implements ComicPageSource {
  ArchiveComicPageSource._(this.session, this.pages, this.cacheCapacity);
  final ArchiveSession session;
  final List<ArchiveEntry> pages;
  final int cacheCapacity;

  /// LRU of in-flight or loaded pages: concurrent requests for the same page
  /// (preload + display) share a single extraction.
  final Map<int, Future<ComicPage>> _cache = {};
  static Future<ArchiveComicPageSource> open(
    ArchiveSession session, {
    int cacheCapacity = 8,
  }) async {
    final pages =
        (await session.listEntries())
            .where(
              (e) =>
                  !e.isDirectory &&
                  isComicImage(e.path) &&
                  !e.path.contains('__MACOSX'),
            )
            .toList()
          ..sort((a, b) => naturalCompare(a.path, b.path));
    return ArchiveComicPageSource._(session, pages, cacheCapacity);
  }

  @override
  Future<int> get pageCount async => pages.length;
  @override
  Future<ComicPage> getPage(int index) {
    final hit = _cache.remove(index);
    if (hit != null) return _cache[index] = hit;
    final page = _load(index);
    _cache[index] = page;
    page.then(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[index], page)) _cache.remove(index);
      },
    );
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return page;
  }

  Future<ComicPage> _load(int index) async {
    final entry = pages[index], source = await session.openEntry(entry);
    final Uint8List bytes;
    if (source is MemoryContentSource) {
      bytes = source.bytes;
    } else {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in await source.openRead()) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }
    return ComicPage(index: index, name: entry.path, bytes: bytes);
  }

  @override
  Future<void> preload(int from, int count) => Future.wait([
    for (var i = from; i < from + count && i < pages.length; i++)
      if (i >= 0) getPage(i),
  ]);

  @override
  Future<void> dispose() async {
    _cache.clear();
    await session.close();
  }
}
