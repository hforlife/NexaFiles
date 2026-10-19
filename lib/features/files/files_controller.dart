import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/errors/app_failure.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import 'file_rules.dart';
import '../../core/performance/perf_trace.dart';

enum FileViewMode { list, grid }

class RootLocation {
  const RootLocation(
      {required this.uri,
      required this.name,
      required this.available,
      this.entry,
      this.favorite = false,
      this.totalBytes,
      this.freeBytes,
      this.discovered = false});
  final Uri uri;
  final String name;
  final bool available, favorite, discovered;
  final StorageEntry? entry;
  final int? totalBytes, freeBytes;
}

class NavigationNode {
  const NavigationNode(this.entry);
  final StorageEntry entry;
}

class FileManagerState {
  const FileManagerState(
      {this.loading = false,
      this.showHidden = false,
      this.roots = const [],
      this.path = const [],
      this.entries = const [],
      this.selected = const {},
      this.query = '',
      this.viewMode = FileViewMode.list,
      this.sort = FileSort.name,
      this.direction = SortDirection.ascending,
      this.failure});
  final bool loading, showHidden;
  final List<RootLocation> roots;
  final List<NavigationNode> path;
  final List<StorageEntry> entries;
  final Set<Uri> selected;
  final String query;
  final FileViewMode viewMode;
  final FileSort sort;
  final SortDirection direction;
  final AppFailure? failure;
  bool get browsing => path.isNotEmpty;
  bool get selecting => selected.isNotEmpty;
  StorageEntry? get current => path.isEmpty ? null : path.last.entry;
  List<StorageEntry> get visibleEntries {
    var filtered = showHidden
        ? entries
        : entries.where((e) => !isHiddenFileName(e.displayName));
    if (query.trim().isNotEmpty)
      filtered = filtered.where((e) =>
          e.displayName.toLowerCase().contains(query.trim().toLowerCase()));
    return sortEntries(filtered, sort, direction);
  }

  FileManagerState copyWith(
          {bool? loading,
          bool? showHidden,
          List<RootLocation>? roots,
          List<NavigationNode>? path,
          List<StorageEntry>? entries,
          Set<Uri>? selected,
          String? query,
          FileViewMode? viewMode,
          FileSort? sort,
          SortDirection? direction,
          AppFailure? failure,
          bool clearFailure = false}) =>
      FileManagerState(
          loading: loading ?? this.loading,
          showHidden: showHidden ?? this.showHidden,
          roots: roots ?? this.roots,
          path: path ?? this.path,
          entries: entries ?? this.entries,
          selected: selected ?? this.selected,
          query: query ?? this.query,
          viewMode: viewMode ?? this.viewMode,
          sort: sort ?? this.sort,
          direction: direction ?? this.direction,
          failure: clearFailure ? null : failure ?? this.failure);
}

bool isHiddenFileName(String name) =>
    name.startsWith('.') && name != '.' && name != '..';
final filesControllerProvider =
    StateNotifierProvider<FilesController, FileManagerState>((ref) =>
        FilesController(
            ref.read(storageRepositoryProvider), ref.read(databaseProvider))
          ..initialize());

class FilesController extends StateNotifier<FileManagerState> {
  FilesController(this.storage, this.database)
      : super(const FileManagerState());
  final StorageRepository storage;
  final AppDatabase database;
  static const _viewKey = 'files.view_mode',
      _sortKey = 'files.sort',
      _directionKey = 'files.sort_direction',
      _hiddenKey = 'files.show_hidden';
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
        showHidden: prefs.getBool(_hiddenKey) ?? false,
        viewMode: FileViewMode.values
            .byName(prefs.getString(_viewKey) ?? FileViewMode.list.name),
        sort: FileSort.values
            .byName(prefs.getString(_sortKey) ?? FileSort.name.name),
        direction: SortDirection.values.byName(
            prefs.getString(_directionKey) ?? SortDirection.ascending.name));
    await loadRoots();
  }

  Future<void> loadRoots() async {
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      var records = await database.roots();
      final favorites = await database.favoriteUris(),
          persisted = await storage.grantedRoots();
      final known = records.map((e) => e.uri).toSet();
      for (final entry in persisted) {
        if (!known.contains('${entry.uri}'))
          await database.upsertRoot('${entry.uri}', entry.displayName);
      }
      records = await database.roots();
      final byUri = {for (final entry in persisted) '${entry.uri}': entry};
      final roots = [
        for (final record in records)
          RootLocation(
              uri: Uri.parse(record.uri),
              name: record.name,
              available: byUri.containsKey(record.uri),
              entry: byUri[record.uri],
              favorite: favorites.contains(record.uri))
      ];
      state = state.copyWith(loading: false, roots: roots);
    } catch (e) {
      state = state.copyWith(loading: false, failure: mapFailure(e));
    }
  }

  Future<void> addLocation() async {
    try {
      final entry = await storage.pickDirectory();
      if (entry == null) return;
      await database.upsertRoot('${entry.uri}', entry.displayName);
      await loadRoots();
    } catch (e) {
      state = state.copyWith(failure: mapFailure(e));
    }
  }

  Future<void> removeRoot(RootLocation root) async {
    await database.removeRoot('${root.uri}');
    try {
      await storage.releaseRoot(root.uri);
    } catch (_) {}
    if (state.path.isNotEmpty && state.path.first.entry.uri == root.uri)
      state = state.copyWith(path: [], entries: [], selected: {});
    await loadRoots();
  }

  Future<void> toggleFavorite(RootLocation root) async {
    await database.setFavorite('${root.uri}', root.name, !root.favorite);
    await loadRoots();
  }

  Future<void> openRoot(RootLocation root) async {
    if (root.discovered && !root.available) {
      await addLocation();
      return;
    }
    if (!root.available || root.entry == null) {
      state = state.copyWith(
          failure: const PermissionFailure(
              'Emplacement inaccessible. Autorisez-le à nouveau ou retirez-le.'));
      return;
    }
    state = state
        .copyWith(path: [NavigationNode(root.entry!)], selected: {}, query: '');
    await refresh();
  }

  Future<void> openFolder(StorageEntry folder) async {
    state = state.copyWith(
        path: [...state.path, NavigationNode(folder)], selected: {}, query: '');
    await refresh();
  }

  Future<bool> goBack() async {
    if (state.selecting) {
      clearSelection();
      return true;
    }
    if (state.path.length > 1) {
      state = state.copyWith(
          path: state.path.sublist(0, state.path.length - 1),
          selected: {},
          query: '');
      await refresh();
      return true;
    }
    if (state.path.isNotEmpty) {
      state = state.copyWith(path: [], entries: [], selected: {}, query: '');
      return true;
    }
    return false;
  }

  Future<void> refresh() async {
    final current = state.current;
    if (current == null) {
      await loadRoots();
      return;
    }
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      final entries = await PerfTrace.measure(
          'directory.listChildren', () => storage.list(current.uri));
      state = state.copyWith(loading: false, entries: entries, selected: {});
      assert(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('[PERF] directory firstPaint entries=${entries.length}');
        });
        return true;
      }());
    } catch (e) {
      state = state.copyWith(loading: false, failure: mapFailure(e));
    }
  }

  void toggleSelection(StorageEntry entry) {
    final values = {...state.selected};
    values.contains(entry.uri)
        ? values.remove(entry.uri)
        : values.add(entry.uri);
    state = state.copyWith(selected: values);
  }

  void selectAll() =>
      state = state.copyWith(selected: state.entries.map((e) => e.uri).toSet());
  void clearSelection() => state = state.copyWith(selected: {});
  List<StorageEntry> get selectedEntries =>
      state.entries.where((e) => state.selected.contains(e.uri)).toList();
  void search(String value) => state = state.copyWith(query: value);
  Future<void> setShowHidden(bool value) async {
    state = state.copyWith(showHidden: value);
    await (await SharedPreferences.getInstance()).setBool(_hiddenKey, value);
  }

  Future<void> setViewMode(FileViewMode value) async {
    state = state.copyWith(viewMode: value);
    await (await SharedPreferences.getInstance())
        .setString(_viewKey, value.name);
  }

  Future<void> setSort(FileSort value) async {
    state = state.copyWith(sort: value);
    await (await SharedPreferences.getInstance())
        .setString(_sortKey, value.name);
  }

  Future<void> toggleDirection() async {
    final value = state.direction == SortDirection.ascending
        ? SortDirection.descending
        : SortDirection.ascending;
    state = state.copyWith(direction: value);
    await (await SharedPreferences.getInstance())
        .setString(_directionKey, value.name);
  }

  Future<void> createFolder(String name) async {
    final error = validateEntryName(name);
    if (error != null) throw StorageFailure(error);
    final current = state.current;
    if (current == null) throw const StorageFailure('Aucun dossier ouvert');
    if (state.entries
        .any((e) => e.displayName.toLowerCase() == name.trim().toLowerCase()))
      throw const StorageFailure('Un élément porte déjà ce nom.');
    await storage.createDirectory(current.uri, name.trim());
    await refresh();
  }

  Future<void> rename(StorageEntry entry, String name) async {
    final error = validateEntryName(name);
    if (error != null) throw StorageFailure(error);
    if (state.entries.any((e) =>
        e.uri != entry.uri &&
        e.displayName.toLowerCase() == name.trim().toLowerCase()))
      throw const StorageFailure('Un élément porte déjà ce nom.');
    await storage.rename(entry.uri, name.trim());
    await refresh();
  }
}
