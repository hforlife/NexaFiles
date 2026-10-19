import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../shared/formatters.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());
  @override
  int get schemaVersion => 5;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await customStatement(
            'CREATE TABLE library_items (id TEXT PRIMARY KEY, source_uri TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, detected_format TEXT NOT NULL, mime_type TEXT, size INTEGER, modified_at INTEGER, cover_cache_key TEXT, last_opened_at INTEGER, added_at INTEGER NOT NULL DEFAULT 0, title TEXT, author TEXT, favorite INTEGER NOT NULL DEFAULT 0, reading_status TEXT, unavailable INTEGER NOT NULL DEFAULT 0, scan_root_uri TEXT)');
        await customStatement(
            'CREATE TABLE reading_progress (item_id TEXT PRIMARY KEY REFERENCES library_items(id) ON DELETE CASCADE, locator_json TEXT NOT NULL, fraction REAL, updated_at INTEGER NOT NULL)');
        await customStatement(
            'CREATE TABLE bookmarks (id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE, locator_json TEXT NOT NULL, label TEXT, created_at INTEGER NOT NULL)');
        await customStatement(
            'CREATE TABLE recent_items (item_id TEXT PRIMARY KEY REFERENCES library_items(id) ON DELETE CASCADE, opened_at INTEGER NOT NULL)');
        await customStatement(
            'CREATE TABLE favorite_folders (uri TEXT PRIMARY KEY, display_name TEXT NOT NULL, added_at INTEGER NOT NULL)');
        await customStatement(
            'CREATE TABLE reader_preferences (item_id TEXT PRIMARY KEY, reading_mode TEXT NOT NULL, reading_direction TEXT NOT NULL, fit_mode TEXT NOT NULL)');
        await customStatement(
            'CREATE TABLE library_scan_roots (uri TEXT PRIMARY KEY, display_name TEXT NOT NULL, added_at INTEGER NOT NULL, last_scan_at INTEGER)');
        await customStatement(
            'CREATE TABLE collections (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL)');
        await customStatement(
            'CREATE TABLE collection_items (collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE, item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE, added_at INTEGER NOT NULL, PRIMARY KEY(collection_id,item_id))');
      }, onUpgrade: (m, from, to) async {
        if (from < 2) {
          await customStatement(
              'CREATE TABLE IF NOT EXISTS favorite_folders (uri TEXT PRIMARY KEY, display_name TEXT NOT NULL, added_at INTEGER NOT NULL)');
        }
        if (from < 3) {
          await customStatement(
              'CREATE TABLE IF NOT EXISTS reader_preferences (item_id TEXT PRIMARY KEY, reading_mode TEXT NOT NULL, reading_direction TEXT NOT NULL, fit_mode TEXT NOT NULL)');
        }
        if (from < 4) {
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN added_at INTEGER NOT NULL DEFAULT 0');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN title TEXT');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN author TEXT');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN reading_status TEXT');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN unavailable INTEGER NOT NULL DEFAULT 0');
          await customStatement(
              'ALTER TABLE library_items ADD COLUMN scan_root_uri TEXT');
          await customStatement(
              'CREATE TABLE library_scan_roots (uri TEXT PRIMARY KEY, display_name TEXT NOT NULL, added_at INTEGER NOT NULL, last_scan_at INTEGER)');
          await customStatement(
              'CREATE TABLE collections (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL)');
          await customStatement(
              'CREATE TABLE collection_items (collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE, item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE, added_at INTEGER NOT NULL, PRIMARY KEY(collection_id,item_id))');
        }
        if (from < 5) {
          // v5 drops SAF (content://) identities for direct file paths. Those
          // rows can no longer be opened; foreign keys are not enforced yet
          // during migration, so children are cleared explicitly.
          for (final table in [
            'reading_progress',
            'bookmarks',
            'recent_items',
            'collection_items',
            'reader_preferences'
          ]) {
            await customStatement(
                "DELETE FROM $table WHERE item_id LIKE 'content:%'");
          }
          await customStatement(
              "DELETE FROM library_items WHERE source_uri LIKE 'content:%'");
          await customStatement(
              "DELETE FROM favorite_folders WHERE uri LIKE 'content:%'");
          await customStatement(
              "DELETE FROM library_scan_roots WHERE uri LIKE 'content:%'");
          await customStatement('DROP TABLE IF EXISTS library_roots');
        }
      }, beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      });

  Future<void> setFavorite(String uri, String name, bool favorite) => favorite
      ? customStatement(
          'INSERT OR REPLACE INTO favorite_folders(uri,display_name,added_at) VALUES(?,?,?)',
          [uri, name, DateTime.now().millisecondsSinceEpoch])
      : customStatement('DELETE FROM favorite_folders WHERE uri=?', [uri]);
  Future<List<RootRecord>> favoriteFolders() async => (await customSelect(
              'SELECT uri,display_name,added_at FROM favorite_folders ORDER BY display_name COLLATE NOCASE')
          .get())
      .map((r) => RootRecord(
          r.read<String>('uri'),
          r.read<String>('display_name'),
          DateTime.fromMillisecondsSinceEpoch(r.read<int>('added_at'))))
      .toList();
  Future<void> recordRecent(
      {required String id,
      required String uri,
      required String name,
      required String format,
      String? mime,
      int? size}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await customStatement(
          'INSERT INTO library_items(id,source_uri,display_name,detected_format,mime_type,size,last_opened_at,added_at,title) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET source_uri=excluded.source_uri,display_name=excluded.display_name,detected_format=excluded.detected_format,mime_type=excluded.mime_type,size=excluded.size,last_opened_at=excluded.last_opened_at,unavailable=0',
          [id, uri, name, format, mime, size, now, now, fallbackTitle(name)]);
      await customStatement(
          'INSERT INTO recent_items(item_id,opened_at) VALUES(?,?) ON CONFLICT(item_id) DO UPDATE SET opened_at=excluded.opened_at',
          [id, now]);
    });
  }

  Future<void> updateCover(String itemId, String key) => customStatement(
      'UPDATE library_items SET cover_cache_key=? WHERE id=?', [key, itemId]);
  Future<List<RecentRecord>> recents() async => (await customSelect(
              'SELECT l.id,l.source_uri,l.display_name,l.detected_format,l.mime_type,l.size,l.cover_cache_key,p.fraction,r.opened_at FROM recent_items r JOIN library_items l ON l.id=r.item_id LEFT JOIN reading_progress p ON p.item_id=l.id ORDER BY r.opened_at DESC LIMIT 100')
          .get())
      .map((r) => RecentRecord(
          id: r.read('id'),
          uri: r.read('source_uri'),
          name: r.read('display_name'),
          format: r.read('detected_format'),
          mime: r.readNullable('mime_type'),
          size: r.readNullable('size'),
          coverKey: r.readNullable('cover_cache_key'),
          fraction: r.readNullable<double>('fraction'),
          openedAt: DateTime.fromMillisecondsSinceEpoch(r.read('opened_at'))))
      .toList();
  Future<void> saveProgress(String itemId, String locator, double fraction) =>
      customStatement(
          'INSERT INTO reading_progress(item_id,locator_json,fraction,updated_at) VALUES(?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET locator_json=excluded.locator_json,fraction=excluded.fraction,updated_at=excluded.updated_at',
          [itemId, locator, fraction, DateTime.now().millisecondsSinceEpoch]);
  Future<ProgressRecord?> progress(String itemId) async {
    final rows = await customSelect(
        'SELECT locator_json,fraction,updated_at FROM reading_progress WHERE item_id=?',
        variables: [Variable.withString(itemId)]).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ProgressRecord(
        r.read('locator_json'),
        r.readNullable<double>('fraction') ?? 0,
        DateTime.fromMillisecondsSinceEpoch(r.read('updated_at')));
  }

  Future<void> saveReaderPreferences(
          String itemId, String mode, String direction, String fit) =>
      customStatement(
          'INSERT INTO reader_preferences(item_id,reading_mode,reading_direction,fit_mode) VALUES(?,?,?,?) ON CONFLICT(item_id) DO UPDATE SET reading_mode=excluded.reading_mode,reading_direction=excluded.reading_direction,fit_mode=excluded.fit_mode',
          [itemId, mode, direction, fit]);
  Future<ReaderPreferencesRecord?> readerPreferences(String itemId) async {
    final rows = await customSelect(
        'SELECT reading_mode,reading_direction,fit_mode FROM reader_preferences WHERE item_id=?',
        variables: [Variable.withString(itemId)]).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ReaderPreferencesRecord(r.read('reading_mode'),
        r.read('reading_direction'), r.read('fit_mode'));
  }

  Future<
      List<
          ContinueReadingRecord>> continueReading() async => (await customSelect(
              "SELECT l.id,l.source_uri,l.display_name,l.detected_format,l.mime_type,l.size,l.cover_cache_key,p.locator_json,p.fraction,p.updated_at FROM reading_progress p JOIN library_items l ON l.id=p.item_id WHERE l.detected_format IN ('comic','pdf','epub','text','markdown') ORDER BY p.updated_at DESC LIMIT 30")
          .get())
      .map((r) => ContinueReadingRecord(
          id: r.read('id'),
          uri: r.read('source_uri'),
          name: r.read('display_name'),
          format: r.read('detected_format'),
          mime: r.readNullable('mime_type'),
          size: r.readNullable('size'),
          coverKey: r.readNullable('cover_cache_key'),
          locator: r.read('locator_json'),
          fraction: r.readNullable<double>('fraction') ?? 0,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(r.read('updated_at'))))
      .toList();
  Future<void> addBookmark(String itemId, String locator, {String? label}) =>
      customStatement(
          'INSERT INTO bookmarks(id,item_id,locator_json,label,created_at) VALUES(?,?,?,?,?)',
          [
            '${itemId}_${DateTime.now().microsecondsSinceEpoch}',
            itemId,
            locator,
            label,
            DateTime.now().millisecondsSinceEpoch
          ]);
  Future<List<BookmarkRecord>> bookmarks(String itemId) async =>
      (await customSelect(
              'SELECT id,locator_json,label,created_at FROM bookmarks WHERE item_id=? ORDER BY created_at DESC',
              variables: [
            Variable.withString(itemId)
          ]).get())
          .map((r) => BookmarkRecord(
              r.read('id'),
              r.read('locator_json'),
              r.readNullable('label'),
              DateTime.fromMillisecondsSinceEpoch(r.read('created_at'))))
          .toList();
  Future<void> upsertScanRoot(String uri, String name) => customStatement(
      'INSERT INTO library_scan_roots(uri,display_name,added_at) VALUES(?,?,?) ON CONFLICT(uri) DO UPDATE SET display_name=excluded.display_name',
      [uri, name, DateTime.now().millisecondsSinceEpoch]);
  Future<void> removeScanRoot(String uri) =>
      customStatement('DELETE FROM library_scan_roots WHERE uri=?', [uri]);
  Future<void> finishRootScan(String uri) => customStatement(
      'UPDATE library_scan_roots SET last_scan_at=? WHERE uri=?',
      [DateTime.now().millisecondsSinceEpoch, uri]);
  Future<List<LibraryRootRecord>> scanRoots() async => (await customSelect(
              'SELECT uri,display_name,added_at,last_scan_at FROM library_scan_roots ORDER BY added_at')
          .get())
      .map((r) => LibraryRootRecord(
          r.read('uri'),
          r.read('display_name'),
          DateTime.fromMillisecondsSinceEpoch(r.read('added_at')),
          r.readNullable<int>('last_scan_at') == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('last_scan_at'))))
      .toList();
  Future<LibraryRecord?> libraryItem(String uri) async {
    final rows = await customSelect(
        'SELECT l.*,p.fraction,p.updated_at FROM library_items l LEFT JOIN reading_progress p ON p.item_id=l.id WHERE l.source_uri=?',
        variables: [Variable.withString(uri)]).get();
    return rows.isEmpty ? null : _libraryRecord(rows.first);
  }

  Future<Map<String, LibraryRecord>> libraryItemsByUris(
      Iterable<String> uris) async {
    final values = uris.toSet().toList();
    if (values.isEmpty) return const {};
    final marks = List.filled(values.length, '?').join(',');
    final rows = await customSelect(
            'SELECT l.*,p.fraction,p.updated_at FROM library_items l LEFT JOIN reading_progress p ON p.item_id=l.id WHERE l.source_uri IN ($marks)',
            variables: values.map(Variable.withString).toList())
        .get();
    return {
      for (final row in rows)
        row.read<String>('source_uri'): _libraryRecord(row)
    };
  }

  Future<void> resetProgressAndHistory() => transaction(() async {
        await customStatement('DELETE FROM reading_progress');
        await customStatement('DELETE FROM recent_items');
      });
  Future<void> upsertScanned(
      {required String uri,
      required String name,
      required String format,
      String? mime,
      int? size,
      DateTime? modified,
      String? rootUri,
      String? title,
      String? author}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customStatement(
        'INSERT INTO library_items(id,source_uri,display_name,detected_format,mime_type,size,modified_at,added_at,title,author,scan_root_uri,unavailable) VALUES(?,?,?,?,?,?,?,?,?,?,?,0) ON CONFLICT(source_uri) DO UPDATE SET display_name=excluded.display_name,detected_format=excluded.detected_format,mime_type=excluded.mime_type,size=excluded.size,modified_at=excluded.modified_at,title=COALESCE(excluded.title,library_items.title),author=COALESCE(excluded.author,library_items.author),scan_root_uri=excluded.scan_root_uri,unavailable=0',
        [
          uri,
          uri,
          name,
          format,
          mime,
          size,
          modified?.millisecondsSinceEpoch,
          now,
          title ?? fallbackTitle(name),
          author,
          rootUri
        ]);
  }

  Future<void> markRootItemsUnavailable(
      String rootUri, Set<String> seen) async {
    final rows = await customSelect(
        'SELECT source_uri FROM library_items WHERE scan_root_uri=?',
        variables: [Variable.withString(rootUri)]).get();
    for (final row in rows) {
      final uri = row.read<String>('source_uri');
      if (!seen.contains(uri)) {
        await customStatement(
            'UPDATE library_items SET unavailable=1 WHERE source_uri=?', [uri]);
      }
    }
  }

  Future<List<LibraryRecord>> libraryItems() async => (await customSelect(
              'SELECT l.*,p.fraction,p.updated_at FROM library_items l LEFT JOIN reading_progress p ON p.item_id=l.id ORDER BY l.added_at DESC')
          .get())
      .map(_libraryRecord)
      .toList();
  Future<void> setLibraryFavorite(String id, bool value) => customStatement(
      'UPDATE library_items SET favorite=? WHERE id=?', [value ? 1 : 0, id]);
  Future<void> setReadingStatus(String id, String? value) => customStatement(
      'UPDATE library_items SET reading_status=? WHERE id=?', [value, id]);
  Future<void> removeLibraryItem(String id) =>
      customStatement('DELETE FROM library_items WHERE id=?', [id]);
  Future<void> createCollection(String id, String name) => customStatement(
      'INSERT INTO collections(id,name,created_at) VALUES(?,?,?)',
      [id, name.trim(), DateTime.now().millisecondsSinceEpoch]);
  Future<void> renameCollection(String id, String name) => customStatement(
      'UPDATE collections SET name=? WHERE id=?', [name.trim(), id]);
  Future<void> deleteCollection(String id) =>
      customStatement('DELETE FROM collections WHERE id=?', [id]);
  Future<List<CollectionRecord>> collections() async => (await customSelect(
              'SELECT c.id,c.name,c.created_at,COUNT(ci.item_id) AS item_count FROM collections c LEFT JOIN collection_items ci ON ci.collection_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE')
          .get())
      .map((r) => CollectionRecord(
          r.read('id'),
          r.read('name'),
          r.read<int>('item_count'),
          DateTime.fromMillisecondsSinceEpoch(r.read('created_at'))))
      .toList();
  Future<void> addToCollection(String collectionId, String itemId) =>
      customStatement(
          'INSERT OR IGNORE INTO collection_items(collection_id,item_id,added_at) VALUES(?,?,?)',
          [collectionId, itemId, DateTime.now().millisecondsSinceEpoch]);
  Future<void> removeFromCollection(String collectionId, String itemId) =>
      customStatement(
          'DELETE FROM collection_items WHERE collection_id=? AND item_id=?',
          [collectionId, itemId]);
  Future<Set<String>> itemCollections(String itemId) async =>
      (await customSelect(
              'SELECT collection_id FROM collection_items WHERE item_id=?',
              variables: [Variable.withString(itemId)]).get())
          .map((r) => r.read<String>('collection_id'))
          .toSet();
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase(File(p.join(dir.path, 'nexafiles.sqlite')));
    });

class RootRecord {
  const RootRecord(this.uri, this.name, this.addedAt);
  final String uri, name;
  final DateTime addedAt;
}

class RecentRecord {
  const RecentRecord(
      {required this.id,
      required this.uri,
      required this.name,
      required this.format,
      required this.openedAt,
      this.mime,
      this.size,
      this.coverKey,
      this.fraction});
  final String id, uri, name, format;
  final String? mime, coverKey;
  final int? size;
  final double? fraction;
  final DateTime openedAt;
}

class ProgressRecord {
  const ProgressRecord(this.locator, this.fraction, this.updatedAt);
  final String locator;
  final double fraction;
  final DateTime updatedAt;
}

class ReaderPreferencesRecord {
  const ReaderPreferencesRecord(this.mode, this.direction, this.fit);
  final String mode, direction, fit;
}

class ContinueReadingRecord {
  const ContinueReadingRecord(
      {required this.id,
      required this.uri,
      required this.name,
      required this.format,
      required this.locator,
      required this.fraction,
      required this.updatedAt,
      this.mime,
      this.size,
      this.coverKey});
  final String id, uri, name, format, locator;
  final double fraction;
  final DateTime updatedAt;
  final String? mime, coverKey;
  final int? size;
}

class BookmarkRecord {
  const BookmarkRecord(this.id, this.locator, this.label, this.createdAt);
  final String id, locator;
  final String? label;
  final DateTime createdAt;
}

class LibraryRootRecord {
  const LibraryRootRecord(this.uri, this.name, this.addedAt, this.lastScanAt);
  final String uri, name;
  final DateTime addedAt;
  final DateTime? lastScanAt;
}

class LibraryRecord {
  const LibraryRecord(
      {required this.id,
      required this.uri,
      required this.name,
      required this.format,
      required this.addedAt,
      required this.favorite,
      required this.unavailable,
      this.title,
      this.author,
      this.mime,
      this.size,
      this.modifiedAt,
      this.coverKey,
      this.lastOpenedAt,
      this.fraction,
      this.progressUpdatedAt,
      this.manualStatus});
  final String id, uri, name, format;
  final String? title, author, mime, coverKey, manualStatus;
  final int? size;
  final DateTime addedAt;
  final DateTime? modifiedAt, lastOpenedAt, progressUpdatedAt;
  final bool favorite, unavailable;
  final double? fraction;
}

class CollectionRecord {
  const CollectionRecord(this.id, this.name, this.itemCount, this.createdAt);
  final String id, name;
  final int itemCount;
  final DateTime createdAt;
}

LibraryRecord _libraryRecord(QueryRow r) => LibraryRecord(
    id: r.read('id'),
    uri: r.read('source_uri'),
    name: r.read('display_name'),
    format: r.read('detected_format'),
    title: r.readNullable('title'),
    author: r.readNullable('author'),
    mime: r.readNullable('mime_type'),
    size: r.readNullable('size'),
    modifiedAt: r.readNullable<int>('modified_at') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.read('modified_at')),
    coverKey: r.readNullable('cover_cache_key'),
    lastOpenedAt: r.readNullable<int>('last_opened_at') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.read('last_opened_at')),
    addedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('added_at')),
    favorite: r.read<int>('favorite') == 1,
    unavailable: r.read<int>('unavailable') == 1,
    fraction: r.readNullable<double>('fraction'),
    progressUpdatedAt: r.readNullable<int>('updated_at') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.read('updated_at')),
    manualStatus: r.readNullable('reading_status'));
