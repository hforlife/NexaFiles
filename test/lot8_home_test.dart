import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/app/app.dart';
import 'package:nexa_file/core/comics/comic_page_source.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/database/database_provider.dart';
import 'package:nexa_file/core/settings/settings_controller.dart';
import 'package:nexa_file/core/storage/local_storage_repository.dart';
import 'package:nexa_file/core/storage/storage_entry.dart';

const _storage = MethodChannel('nexa_file/storage');

void _mockStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_storage, (call) async {
        switch (call.method) {
          case 'hasAllFilesAccess':
            return true;
          case 'volumes':
            return [
              {
                'path': '/storage/emulated/0',
                'name': 'Stockage interne',
                'primary': true,
                'removable': false,
                'total': 64000000000,
                'free': 16000000000,
              },
            ];
          case 'categoryStats':
            return {
              'images': {'count': 1234, 'bytes': 5000000},
              'books': {'count': 12, 'bytes': 900000},
            };
          case 'categoryFiles':
            return [
              {
                'path': '/storage/emulated/0/Books/One Piece 01.cbz',
                'size': 4200,
                'modified': 1700000000000,
              },
            ];
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_mockStorage);

  group('natural sort', () {
    int cmp(String a, String b) => naturalCompare(a, b).sign;
    test('numbers by value', () {
      expect(cmp('page2.jpg', 'page10.jpg'), -1);
      expect(cmp('Vol 9', 'vol 10'), -1);
      expect(cmp('a', 'b'), -1);
    });
    test('leading zeros and case are ignored', () {
      expect(cmp('p001', 'P1'), 0);
      expect(cmp('p01a', 'p1b'), -1);
    });
    test('numbers beyond 64 bits still compare', () {
      expect(cmp('x99999999999999999999', 'x100000000000000000000'), -1);
    });
    test('a prefix sorts first', () {
      expect(cmp('chapter', 'chapter 1'), -1);
    });
  });

  test('library lists reading formats only', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.recordRecent(
      id: 'file:///photo.jpg',
      uri: 'file:///photo.jpg',
      name: 'photo.jpg',
      format: 'image',
    );
    await db.recordRecent(
      id: 'file:///tome.cbz',
      uri: 'file:///tome.cbz',
      name: 'tome.cbz',
      format: 'comic',
    );
    expect((await db.libraryItems()).map((e) => e.name), ['tome.cbz']);
    expect((await db.recents()).length, 2);
  });

  test('categories are read from the media index', () async {
    final storage = LocalStorageRepository();
    final stats = await storage.categoryStats();
    expect(stats['images']!.count, 1234);
    expect(stats['books']!.bytes, 900000);
    final files = await storage.categoryFiles('books');
    expect(files.single.displayName, 'One Piece 01.cbz');
    expect(files.single.kind, StorageEntryKind.file);
    expect(files.single.mimeType, 'application/vnd.comicbook+zip');
    expect(files.single.size, 4200);
  });

  testWidgets('home shows storage and categories with counts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final database = (await tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      return db;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((_) => settings),
          databaseProvider.overrideWithValue(database),
        ],
        child: const NexaFilesApp(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Stockage interne'), findsOneWidget);
    expect(find.textContaining('libres'), findsOneWidget);
    expect(find.text('Catégories'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('Livres & BD'), findsOneWidget);
  });
}
