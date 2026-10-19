import '../database/app_database.dart';

export '../../shared/formatters.dart' show fallbackTitle;

enum LibraryCategory { all, books, comics, pdf, documents }

enum LibraryFilter { all, inProgress, finished, unread, favorites }

enum LibrarySort { titleAsc, titleDesc, dateAdded, lastRead, progress }

enum ReadingState { notStarted, inProgress, finished }

ReadingState readingState(LibraryRecord item) {
  if (item.manualStatus == 'finished') return ReadingState.finished;
  if (item.manualStatus == 'unread') return ReadingState.notStarted;
  final value = item.fraction ?? 0;
  if (value >= .95) return ReadingState.finished;
  if (value > 0) return ReadingState.inProgress;
  return ReadingState.notStarted;
}

class LibraryRepository {
  LibraryRepository(this.database);
  final AppDatabase database;
  Future<List<LibraryRecord>> query(
          {String search = '',
          LibraryCategory category = LibraryCategory.all,
          LibraryFilter filter = LibraryFilter.all,
          LibrarySort sort = LibrarySort.dateAdded}) async =>
      filterAndSortLibrary(await database.libraryItems(),
          search: search, category: category, filter: filter, sort: sort);
  Future<List<LibraryRecord>> continueReading() async => (await query(
          filter: LibraryFilter.inProgress, sort: LibrarySort.lastRead))
      .where((e) => !e.unavailable)
      .toList();
  Future<void> favorite(LibraryRecord item, bool value) =>
      database.setLibraryFavorite(item.id, value);
  Future<void> status(LibraryRecord item, ReadingState state) =>
      database.setReadingStatus(
          item.id,
          state == ReadingState.finished
              ? 'finished'
              : state == ReadingState.notStarted
                  ? 'unread'
                  : null);
  Future<void> remove(LibraryRecord item) =>
      database.removeLibraryItem(item.id);
}

List<LibraryRecord> filterAndSortLibrary(Iterable<LibraryRecord> source,
    {String search = '',
    LibraryCategory category = LibraryCategory.all,
    LibraryFilter filter = LibraryFilter.all,
    LibrarySort sort = LibrarySort.dateAdded}) {
  final q = search.trim().toLowerCase();
  final values = source.where((e) {
    final categoryOk = switch (category) {
      LibraryCategory.all => true,
      LibraryCategory.books => e.format == 'epub',
      LibraryCategory.comics => e.format == 'comic',
      LibraryCategory.pdf => e.format == 'pdf',
      LibraryCategory.documents => e.format == 'text' || e.format == 'markdown'
    };
    final state = readingState(e);
    final filterOk = switch (filter) {
      LibraryFilter.all => true,
      LibraryFilter.inProgress => state == ReadingState.inProgress,
      LibraryFilter.finished => state == ReadingState.finished,
      LibraryFilter.unread => state == ReadingState.notStarted,
      LibraryFilter.favorites => e.favorite
    };
    return categoryOk &&
        filterOk &&
        (q.isEmpty ||
            '${e.title} ${e.name} ${e.author}'.toLowerCase().contains(q));
  }).toList();
  values.sort((a, b) => switch (sort) {
        LibrarySort.titleAsc => (a.title ?? a.name)
            .toLowerCase()
            .compareTo((b.title ?? b.name).toLowerCase()),
        LibrarySort.titleDesc => (b.title ?? b.name)
            .toLowerCase()
            .compareTo((a.title ?? a.name).toLowerCase()),
        LibrarySort.dateAdded => b.addedAt.compareTo(a.addedAt),
        LibrarySort.lastRead =>
          (b.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
              a.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        LibrarySort.progress => (b.fraction ?? 0).compareTo(a.fraction ?? 0)
      });
  return values;
}

class ReadingProgressRepository {
  ReadingProgressRepository(this.database);
  final AppDatabase database;
  Future<ProgressRecord?> get(String itemId) => database.progress(itemId);
  Future<void> save(String itemId, String locator, double fraction) =>
      database.saveProgress(itemId, locator, fraction);
}

class BookmarkRepository {
  BookmarkRepository(this.database);
  final AppDatabase database;
  Future<List<BookmarkRecord>> list(String itemId) =>
      database.bookmarks(itemId);
  Future<void> add(String itemId, String locator, {String? label}) =>
      database.addBookmark(itemId, locator, label: label);
}

class CollectionRepository {
  CollectionRepository(this.database);
  final AppDatabase database;
  Future<List<CollectionRecord>> list() => database.collections();
  Future<void> create(String name) => database.createCollection(
      'collection_${DateTime.now().microsecondsSinceEpoch}', name);
  Future<void> rename(String id, String name) =>
      database.renameCollection(id, name);
  Future<void> delete(String id) => database.deleteCollection(id);
  Future<void> add(String collectionId, String itemId) =>
      database.addToCollection(collectionId, itemId);
  Future<void> remove(String collectionId, String itemId) =>
      database.removeFromCollection(collectionId, itemId);
  Future<Set<String>> memberships(String itemId) =>
      database.itemCollections(itemId);
}
