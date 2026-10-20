import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/errors/app_failure.dart';
import 'package:nexa_file/core/storage/content_source.dart';
import 'package:nexa_file/core/storage/local_storage_repository.dart';
import 'package:nexa_file/core/storage/mime_types.dart';
import 'package:nexa_file/core/storage/storage_entry.dart';
import 'package:nexa_file/core/trash/trash_service.dart';
import 'package:nexa_file/features/files/file_operation_service.dart';
import 'package:nexa_file/features/files/file_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final storage = LocalStorageRepository();

  Uri at(String relative) => Uri.file('${root.path}/$relative');
  File file(String relative, [String content = 'x']) =>
      File('${root.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
  Future<List<String>> names(String relative) async =>
      (await storage.list(at(relative))).map((e) => e.displayName).toList()
        ..sort();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('nexa_lot3_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('LocalStorageRepository', () {
    test('lists files and folders with size, date and MIME type', () async {
      file('docs/book.epub', 'abc');
      Directory('${root.path}/docs/sub').createSync();
      final entries = await storage.list(at('docs'));
      final book = entries.firstWhere((e) => e.displayName == 'book.epub');
      final sub = entries.firstWhere((e) => e.displayName == 'sub');
      expect(book.kind, StorageEntryKind.file);
      expect(book.size, 3);
      expect(book.mimeType, 'application/epub+zip');
      expect(book.modifiedAt, isNotNull);
      expect(sub.kind, StorageEntryKind.directory);
      expect(sub.size, isNull);
    });

    test('get returns null for a missing path', () async {
      expect(await storage.get(at('nope.pdf')), isNull);
    });

    test('create, rename and refuse to overwrite', () async {
      final dir = await storage.createDirectory(Uri.file(root.path), 'new');
      expect(dir.kind, StorageEntryKind.directory);
      final created = await storage.createFile(
        dir.uri,
        'a.txt',
        utf8.encode('hello'),
      );
      expect(File(created.uri.toFilePath()).readAsStringSync(), 'hello');
      await expectLater(
        storage.createFile(dir.uri, 'a.txt', utf8.encode('')),
        throwsA(isA<StorageFailure>()),
      );
      final renamed = await storage.rename(created.uri, 'b.txt');
      expect(renamed.displayName, 'b.txt');
      expect(await names('new'), ['b.txt']);
    });

    test('copies a whole folder tree', () async {
      file('src/a.txt', 'A');
      file('src/inner/b.txt', 'B');
      Directory('${root.path}/dst').createSync();
      await storage.copy(at('src'), at('dst'));
      expect(File('${root.path}/dst/src/inner/b.txt').readAsStringSync(), 'B');
      expect(File('${root.path}/src/a.txt').existsSync(), isTrue);
    });

    test('moves files and folders in place', () async {
      file('src/inner/b.txt', 'B');
      file('movie.mkv', 'M');
      Directory('${root.path}/dst').createSync();
      await storage.move(at('src'), at('dst'));
      await storage.move(at('movie.mkv'), at('dst'), targetName: 'film.mkv');
      expect(File('${root.path}/dst/src/inner/b.txt').readAsStringSync(), 'B');
      expect(File('${root.path}/dst/film.mkv').readAsStringSync(), 'M');
      expect(Directory('${root.path}/src').existsSync(), isFalse);
      expect(File('${root.path}/movie.mkv').existsSync(), isFalse);
    });

    test('deletes folders recursively', () async {
      file('trash/deep/x.txt');
      await storage.delete(at('trash'));
      expect(Directory('${root.path}/trash').existsSync(), isFalse);
    });

    test('reads only the requested prefix', () async {
      file('doc.pdf', '%PDF-1.7 rest of the file');
      expect(
        utf8.decode(await storage.readPrefix(at('doc.pdf'), length: 8)),
        '%PDF-1.7',
      );
    });

    test('content source uses the file in place, without copying', () async {
      final f = file('comic.cbz', 'zip');
      final entry = (await storage.get(at('comic.cbz')))!;
      final source = storage.sourceFor(entry) as MaterializedContentSource;
      expect((await source.materialize()).path, f.path);
      expect(await source.length, 3);
    });
  });

  group('FileOperationService', () {
    Future<void> run(
      List<String> sources,
      String destination, {
      required bool move,
      required ConflictPolicy policy,
    }) async => FileOperationService(storage)
        .transfer(
          sources: [for (final s in sources) (await storage.get(at(s)))!],
          destination: at(destination),
          move: move,
          conflict: policy,
        )
        .drain<void>();

    test('moving a file into its own folder never deletes it', () async {
      file('dir/keep.txt', 'precious');
      await run(
        ['dir/keep.txt'],
        'dir',
        move: true,
        policy: ConflictPolicy.replace,
      );
      expect(File('${root.path}/dir/keep.txt').readAsStringSync(), 'precious');
      expect(await names('dir'), ['keep.txt']);
    });

    test('copying into the same folder makes a numbered duplicate', () async {
      file('dir/a.txt');
      await run(
        ['dir/a.txt'],
        'dir',
        move: false,
        policy: ConflictPolicy.replace,
      );
      expect(await names('dir'), ['a (1).txt', 'a.txt']);
    });

    test('replace overwrites the existing target', () async {
      file('src/a.txt', 'new');
      file('dst/a.txt', 'old');
      await run(
        ['src/a.txt'],
        'dst',
        move: true,
        policy: ConflictPolicy.replace,
      );
      expect(File('${root.path}/dst/a.txt').readAsStringSync(), 'new');
      expect(await names('dst'), ['a.txt']);
      expect(File('${root.path}/src/a.txt').existsSync(), isFalse);
    });

    test('keep both renames the incoming folder', () async {
      file('src/photos/p.jpg');
      file('dst/photos/q.jpg');
      await run(
        ['src/photos'],
        'dst',
        move: false,
        policy: ConflictPolicy.keepBoth,
      );
      expect(await names('dst'), ['photos', 'photos (1)']);
      expect(await names('dst/photos (1)'), ['p.jpg']);
    });
  });

  test('trash accepts folders and restores them', () async {
    file('books/series/vol1.cbz', 'v1');
    final trash = TrashService(storage);
    final folder = (await storage.get(at('books/series')))!;
    expect(
      await trash.moveToTrash(folder, at('books'), Uri.file(root.path)),
      isTrue,
    );
    expect(Directory('${root.path}/books/series').existsSync(), isFalse);
    final items = await trash.list();
    expect(items.single.name, 'series');
    await trash.restore(items.single);
    expect(File('${root.path}/books/series/vol1.cbz').readAsStringSync(), 'v1');
    expect(await trash.list(), isEmpty);
  });

  test('MIME types come from the extension', () {
    expect(mimeTypeFor('Scan.JPG'), 'image/jpeg');
    expect(mimeTypeFor('tome.cbr'), 'application/vnd.comicbook-rar');
    expect(mimeTypeFor('README'), isNull);
    expect(mimeTypeFor('archive.'), isNull);
  });

  test('v5 migration drops unreachable SAF rows and keeps file rows', () async {
    const saf = 'content://tree/old.epub', local = 'file:///sdcard/new.epub';
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE library_items (id TEXT PRIMARY KEY, '
            'source_uri TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, '
            'detected_format TEXT NOT NULL, mime_type TEXT, size INTEGER, '
            'modified_at INTEGER, cover_cache_key TEXT, last_opened_at INTEGER, '
            'added_at INTEGER NOT NULL DEFAULT 0, title TEXT, author TEXT, '
            'favorite INTEGER NOT NULL DEFAULT 0, reading_status TEXT, '
            'unavailable INTEGER NOT NULL DEFAULT 0, scan_root_uri TEXT)',
          );
          for (final table in ['reading_progress', 'recent_items']) {
            raw.execute(
              'CREATE TABLE $table (item_id TEXT PRIMARY KEY, '
              'locator_json TEXT, fraction REAL, opened_at INTEGER, '
              'updated_at INTEGER)',
            );
          }
          raw.execute(
            'CREATE TABLE bookmarks (id TEXT PRIMARY KEY, item_id TEXT)',
          );
          raw.execute(
            'CREATE TABLE collection_items (collection_id TEXT, '
            'item_id TEXT)',
          );
          raw.execute(
            'CREATE TABLE reader_preferences (item_id TEXT PRIMARY KEY)',
          );
          raw.execute(
            'CREATE TABLE library_roots (uri TEXT PRIMARY KEY, '
            'display_name TEXT NOT NULL, added_at INTEGER NOT NULL)',
          );
          for (final table in ['favorite_folders', 'library_scan_roots']) {
            raw.execute(
              'CREATE TABLE $table (uri TEXT PRIMARY KEY, '
              'display_name TEXT NOT NULL, added_at INTEGER NOT NULL, '
              'last_scan_at INTEGER)',
            );
          }
          for (final uri in [saf, local]) {
            raw.execute(
              "INSERT INTO library_items(id,source_uri,display_name,"
              "detected_format) VALUES('$uri','$uri','book','epub')",
            );
            raw.execute(
              "INSERT INTO reading_progress(item_id,fraction) VALUES('$uri',.5)",
            );
            raw.execute(
              "INSERT INTO favorite_folders VALUES('$uri','d',0,NULL)",
            );
          }
          raw.execute("INSERT INTO library_roots VALUES('$saf','old',0)");
          raw.userVersion = 4;
        },
      ),
    );
    addTearDown(db.close);
    Future<List<String>> column(String sql) async =>
        (await db.customSelect(sql).get())
            .map((r) => r.data.values.first as String)
            .toList();
    expect(await column('SELECT id FROM library_items'), [local]);
    expect(await column('SELECT item_id FROM reading_progress'), [local]);
    expect((await db.favoriteFolders()).map((e) => e.uri), [local]);
    expect(
      await column("SELECT name FROM sqlite_master WHERE name='library_roots'"),
      isEmpty,
    );
  });
}
