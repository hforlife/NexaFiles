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

/// A storage volume shown on the Files home screen.
class RootLocation {
  const RootLocation({
    required this.entry,
    required this.name,
    this.primary = false,
    this.removable = false,
    this.totalBytes,
    this.freeBytes,
  });
  final StorageEntry entry;
  final String name;
  final bool primary, removable;
  final int? totalBytes, freeBytes;
  Uri get uri => entry.uri;
}

/// Well-known folder of the primary volume (Download, DCIM…).
class QuickFolder {
  const QuickFolder(this.folderName, this.label, this.entry);
  final String folderName, label;
  final StorageEntry entry;
}

const standardFolders = [
  ('Download', 'Téléchargements'),
  ('Documents', 'Documents'),
  ('DCIM', 'Appareil photo'),
  ('Pictures', 'Images'),
  ('Music', 'Musique'),
  ('Movies', 'Vidéos'),
];

class NavigationNode {
  const NavigationNode(this.entry);
  final StorageEntry entry;
}

class FileManagerState {
  const FileManagerState({
    this.loading = false,
    this.showHidden = false,
    this.hasAccess,
    this.roots = const [],
    this.quickFolders = const [],
    this.favorites = const [],
    this.path = const [],
    this.entries = const [],
    this.selected = const {},
    this.query = '',
    this.viewMode = FileViewMode.list,
    this.sort = FileSort.name,
    this.direction = SortDirection.ascending,
    this.failure,
  });
  final bool loading, showHidden;

  /// Null until checked; false shows the permission screen.
  final bool? hasAccess;
  final List<RootLocation> roots;
  final List<QuickFolder> quickFolders;
  final List<StorageEntry> favorites;
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
  bool isFavorite(Uri uri) => favorites.any((e) => e.uri == uri);
  StorageEntry? get current => path.isEmpty ? null : path.last.entry;
  List<StorageEntry> get visibleEntries {
    var filtered = showHidden
        ? entries
        : entries.where((e) => !isHiddenFileName(e.displayName));
    if (query.trim().isNotEmpty) {
      filtered = filtered.where(
        (e) => e.displayName.toLowerCase().contains(query.trim().toLowerCase()),
      );
    }
    return sortEntries(filtered, sort, direction);
  }

  FileManagerState copyWith({
    bool? loading,
    bool? showHidden,
    bool? hasAccess,
    List<RootLocation>? roots,
    List<QuickFolder>? quickFolders,
    List<StorageEntry>? favorites,
    List<NavigationNode>? path,
    List<StorageEntry>? entries,
    Set<Uri>? selected,
    String? query,
    FileViewMode? viewMode,
    FileSort? sort,
    SortDirection? direction,
    AppFailure? failure,
    bool clearFailure = false,
  }) => FileManagerState(
    loading: loading ?? this.loading,
    showHidden: showHidden ?? this.showHidden,
    hasAccess: hasAccess ?? this.hasAccess,
    roots: roots ?? this.roots,
    quickFolders: quickFolders ?? this.quickFolders,
    favorites: favorites ?? this.favorites,
    path: path ?? this.path,
    entries: entries ?? this.entries,
    selected: selected ?? this.selected,
    query: query ?? this.query,
    viewMode: viewMode ?? this.viewMode,
    sort: sort ?? this.sort,
    direction: direction ?? this.direction,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

bool isHiddenFileName(String name) =>
    name.startsWith('.') && name != '.' && name != '..';
final filesControllerProvider =
    StateNotifierProvider<FilesController, FileManagerState>(
      (ref) => FilesController(
        ref.read(storageRepositoryProvider),
        ref.read(databaseProvider),
      )..initialize(),
    );

class FilesController extends StateNotifier<FileManagerState> {
  FilesController(this.storage, this.database)
    : super(const FileManagerState());
  final StorageRepository storage;
  final AppDatabase database;

  static const _viewKey = 'files.view_mode',
      _sortKey = 'files.sort',
      _directionKey = 'files.sort_direction',
      _hiddenKey = 'files.show_hidden',
      _layoutPrefix = 'files.layout.';
  SharedPreferences? _prefs;

  Future<void> initialize() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = state.copyWith(
      showHidden: prefs.getBool(_hiddenKey) ?? false,
      viewMode: FileViewMode.values.byName(
        prefs.getString(_viewKey) ?? FileViewMode.list.name,
      ),
      sort: FileSort.values.byName(
        prefs.getString(_sortKey) ?? FileSort.name.name,
      ),
      direction: SortDirection.values.byName(
        prefs.getString(_directionKey) ?? SortDirection.ascending.name,
      ),
    );
    await loadRoots();
  }

  /// Volumes, standard folders and favorites; also re-checks the permission.
  Future<void> loadRoots() async {
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      final access = await storage.hasAllFilesAccess();
      if (!mounted) return;
      if (!access) {
        state = state.copyWith(
          loading: false,
          hasAccess: false,
          roots: [],
          quickFolders: [],
          favorites: [],
        );
        return;
      }
      final volumes = await storage.volumes();
      final roots = [
        for (final v in volumes)
          RootLocation(
            entry: StorageEntry(
              uri: Uri.file(v.path),
              displayName: v.name,
              kind: StorageEntryKind.directory,
            ),
            name: v.name,
            primary: v.primary,
            removable: v.removable,
            totalBytes: v.totalBytes,
            freeBytes: v.freeBytes,
          ),
      ];
      final primary = volumes.where((v) => v.primary).firstOrNull;
      final quick = <QuickFolder>[];
      if (primary != null) {
        for (final (folder, label) in standardFolders) {
          final entry = await storage.get(Uri.file('${primary.path}/$folder'));
          if (entry?.kind == StorageEntryKind.directory) {
            quick.add(QuickFolder(folder, label, entry!));
          }
        }
      }
      final favorites = <StorageEntry>[];
      for (final record in await database.favoriteFolders()) {
        final entry = await storage.get(Uri.parse(record.uri));
        if (entry?.kind == StorageEntryKind.directory) favorites.add(entry!);
      }
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        hasAccess: true,
        roots: roots,
        quickFolders: quick,
        favorites: favorites,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, failure: mapFailure(e));
    }
  }

  /// Opens the system permission screen; [loadRoots] runs again on resume.
  Future<void> requestAccess() async {
    try {
      await storage.requestAllFilesAccess();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(failure: mapFailure(e));
    }
  }

  Future<void> toggleFavorite(StorageEntry folder) async {
    await database.setFavorite(
      '${folder.uri}',
      folder.displayName,
      !state.isFavorite(folder.uri),
    );
    if (!mounted) return;
    final favorites = state.isFavorite(folder.uri)
        ? state.favorites.where((e) => e.uri != folder.uri).toList()
        : ([...state.favorites, folder]..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          ));
    state = state.copyWith(favorites: favorites);
  }

  Future<void> openRoot(RootLocation root) async {
    state = state.copyWith(
      path: [NavigationNode(root.entry)],
      selected: {},
      query: '',
    );
    await refresh();
  }

  /// Opens any folder with a full breadcrumb from its volume root.
  Future<void> openDirectory(StorageEntry folder) async {
    final target = folder.uri.toFilePath();
    final root = state.roots
        .where(
          (r) =>
              target == r.uri.toFilePath() ||
              target.startsWith('${r.uri.toFilePath()}/'),
        )
        .firstOrNull;
    final nodes = <NavigationNode>[];
    if (root != null) {
      nodes.add(NavigationNode(root.entry));
      var path = root.uri.toFilePath();
      for (final segment
          in target
              .substring(path.length)
              .split('/')
              .where((e) => e.isNotEmpty)) {
        path = '$path/$segment';
        nodes.add(
          NavigationNode(
            StorageEntry(
              uri: Uri.file(path),
              displayName: segment,
              kind: StorageEntryKind.directory,
            ),
          ),
        );
      }
    } else {
      nodes.add(NavigationNode(folder));
    }
    state = state.copyWith(path: nodes, selected: {}, query: '');
    await refresh();
  }

  Future<void> openFolder(StorageEntry folder) async {
    state = state.copyWith(
      path: [...state.path, NavigationNode(folder)],
      selected: {},
      query: '',
    );
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
        query: '',
      );
      await refresh();
      return true;
    }
    if (state.path.isNotEmpty) {
      state = state.copyWith(path: [], entries: [], selected: {}, query: '');
      return true;
    }
    return false;
  }

  /// Jumps straight to breadcrumb level [index] with a single listing.
  Future<void> goTo(int index) async {
    if (index < 0 || index >= state.path.length - 1) return;
    state = state.copyWith(
      path: state.path.sublist(0, index + 1),
      selected: {},
      query: '',
    );
    await refresh();
  }

  /// Each folder remembers its own view and sort; unknown folders follow
  /// the last choice made anywhere.
  void _applyFolderLayout(StorageEntry folder) {
    final raw = _prefs?.getString('$_layoutPrefix${folder.uri.toFilePath()}');
    if (raw == null) return;
    final parts = raw.split('|');
    if (parts.length != 3) return;
    state = state.copyWith(
      viewMode: FileViewMode.values.asNameMap()[parts[0]] ?? state.viewMode,
      sort: FileSort.values.asNameMap()[parts[1]] ?? state.sort,
      direction: SortDirection.values.asNameMap()[parts[2]] ?? state.direction,
    );
  }

  /// Saves the current layout for the open folder and as the default.
  Future<void> _saveLayout() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(_viewKey, state.viewMode.name);
    await prefs.setString(_sortKey, state.sort.name);
    await prefs.setString(_directionKey, state.direction.name);
    final current = state.current;
    if (current != null) {
      await prefs.setString(
        '$_layoutPrefix${current.uri.toFilePath()}',
        '${state.viewMode.name}|${state.sort.name}|${state.direction.name}',
      );
    }
  }

  Future<void> refresh() async {
    final current = state.current;
    if (current == null) {
      await loadRoots();
      return;
    }
    _applyFolderLayout(current);
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      final entries = await PerfTrace.measure(
        'directory.listChildren',
        () => storage.list(current.uri),
      );
      if (!mounted) return;
      state = state.copyWith(loading: false, entries: entries, selected: {});
      assert(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('[PERF] directory firstPaint entries=${entries.length}');
        });
        return true;
      }());
    } catch (e) {
      if (!mounted) return;
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

  /// Selects only what the user can see (hidden files and search filter apply).
  void selectAll() => state = state.copyWith(
    selected: state.visibleEntries.map((e) => e.uri).toSet(),
  );
  void clearSelection() => state = state.copyWith(selected: {});

  /// Selected entries that are currently visible; never acts on hidden ones.
  List<StorageEntry> get selectedEntries => state.visibleEntries
      .where((e) => state.selected.contains(e.uri))
      .toList();
  void search(String value) => _pruneSelection(state.copyWith(query: value));
  void _pruneSelection(FileManagerState next) {
    final visible = next.visibleEntries.map((e) => e.uri).toSet();
    state = next.copyWith(selected: next.selected.intersection(visible));
  }

  Future<void> setShowHidden(bool value) async {
    _pruneSelection(state.copyWith(showHidden: value));
    await (await SharedPreferences.getInstance()).setBool(_hiddenKey, value);
  }

  Future<void> setViewMode(FileViewMode value) async {
    state = state.copyWith(viewMode: value);
    await _saveLayout();
  }

  Future<void> setSort(FileSort value) async {
    state = state.copyWith(sort: value);
    await _saveLayout();
  }

  Future<void> toggleDirection() async {
    state = state.copyWith(
      direction: state.direction == SortDirection.ascending
          ? SortDirection.descending
          : SortDirection.ascending,
    );
    await _saveLayout();
  }

  Future<void> createFolder(String name) async {
    final error = validateEntryName(name);
    if (error != null) throw StorageFailure(error);
    final current = state.current;
    if (current == null) throw const StorageFailure('Aucun dossier ouvert');
    if (state.entries.any(
      (e) => e.displayName.toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const StorageFailure('Un élément porte déjà ce nom.');
    }
    await storage.createDirectory(current.uri, name.trim());
    await refresh();
  }

  Future<void> rename(StorageEntry entry, String name) async {
    final error = validateEntryName(name);
    if (error != null) throw StorageFailure(error);
    if (state.entries.any(
      (e) =>
          e.uri != entry.uri &&
          e.displayName.toLowerCase() == name.trim().toLowerCase(),
    )) {
      throw const StorageFailure('Un élément porte déjà ce nom.');
    }
    await storage.rename(entry.uri, name.trim());
    await refresh();
  }
}
