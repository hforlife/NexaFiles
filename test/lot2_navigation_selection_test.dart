import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/storage/storage_entry.dart';
import 'package:nexa_file/core/storage/storage_repository.dart';
import 'package:nexa_file/features/files/files_controller.dart';

StorageEntry _file(String name) => StorageEntry(
    uri: Uri.parse('content://tree/root/$name'),
    displayName: name,
    kind: StorageEntryKind.file);

StorageEntry _dir(String name) => StorageEntry(
    uri: Uri.parse('content://tree/$name'),
    displayName: name,
    kind: StorageEntryKind.directory);

/// Only `list` is exercised; every listing returns the same children.
class _FakeStorage implements StorageRepository {
  _FakeStorage(this.children);
  final List<StorageEntry> children;
  int listCalls = 0;
  @override
  Future<List<StorageEntry>> list(Uri directoryUri) async {
    listCalls++;
    return children;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeStorage storage;
  late AppDatabase database;
  late FilesController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = _FakeStorage(
        [_file('.secret.pdf'), _file('book.epub'), _file('notes.txt')]);
    database = AppDatabase(NativeDatabase.memory());
    controller = FilesController(storage, database);
    await controller.openFolder(_dir('root'));
  });
  tearDown(() => database.close());

  test('select all never includes hidden files', () {
    controller.selectAll();
    expect(controller.selectedEntries.map((e) => e.displayName),
        unorderedEquals(['book.epub', 'notes.txt']));
    expect(controller.state.selected.length, 2);
  });

  test('select all respects the search filter', () {
    controller.search('book');
    controller.selectAll();
    expect(controller.selectedEntries.map((e) => e.displayName), ['book.epub']);
  });

  test('narrowing the search drops entries that are no longer visible', () {
    controller.selectAll();
    controller.search('notes');
    expect(controller.state.selected,
        {Uri.parse('content://tree/root/notes.txt')});
  });

  test('hiding hidden files drops them from the selection', () async {
    await controller.setShowHidden(true);
    controller.selectAll();
    expect(controller.state.selected.length, 3);
    await controller.setShowHidden(false);
    expect(controller.selectedEntries.map((e) => e.displayName),
        unorderedEquals(['book.epub', 'notes.txt']));
    expect(controller.state.selected.length, 2);
  });

  test('breadcrumb jump lists the target folder only once', () async {
    await controller.openFolder(_dir('a'));
    await controller.openFolder(_dir('b'));
    storage.listCalls = 0;
    await controller.goTo(0);
    expect(controller.state.path.length, 1);
    expect(storage.listCalls, 1);
  });

  test('back clears the selection before leaving the folder', () async {
    controller.selectAll();
    expect(await controller.goBack(), isTrue);
    expect(controller.state.selecting, isFalse);
    expect(controller.state.browsing, isTrue);
  });

  test('async work finishing after dispose does not throw', () async {
    final pending = controller.refresh();
    controller.dispose();
    await expectLater(pending, completes);
  });
}
