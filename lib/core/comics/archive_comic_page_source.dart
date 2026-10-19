import 'dart:typed_data';
import '../archives/archive_core.dart';
import 'comic_page_source.dart';

class ArchiveComicPageSource implements ComicPageSource {
  ArchiveComicPageSource._(this.session, this.pages, this.cacheCapacity);
  final ArchiveSession session;
  final List<ArchiveEntry> pages;
  final int cacheCapacity;
  final Map<int, ComicPage> _cache = {};
  static Future<ArchiveComicPageSource> open(ArchiveSession session,
      {int cacheCapacity = 4}) async {
    final pages = (await session.listEntries())
        .where((e) =>
            !e.isDirectory &&
            isComicImage(e.path) &&
            !e.path.contains('__MACOSX'))
        .toList()
      ..sort((a, b) => naturalCompare(a.path, b.path));
    return ArchiveComicPageSource._(session, pages, cacheCapacity);
  }

  @override
  Future<int> get pageCount async => pages.length;
  @override
  Future<ComicPage> getPage(int index) async {
    final hit = _cache.remove(index);
    if (hit != null) {
      _cache[index] = hit;
      return hit;
    }
    final entry = pages[index],
        source = await session.openEntry(entry),
        chunks = await source.openRead(),
        bytes = <int>[];
    await for (final chunk in chunks) {
      bytes.addAll(chunk);
    }
    final page = ComicPage(
        index: index, name: entry.path, bytes: Uint8List.fromList(bytes));
    _cache[index] = page;
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return page;
  }

  @override
  Future<void> preload(int from, int count) async {
    for (var i = from; i < from + count && i < pages.length; i++) {
      if (i >= 0) await getPage(i);
    }
  }

  @override
  Future<void> dispose() async {
    _cache.clear();
    await session.close();
  }
}
