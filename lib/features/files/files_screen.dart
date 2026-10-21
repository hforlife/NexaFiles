import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/app_router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/database/database_provider.dart';
import '../../core/storage/storage_entry.dart';
import '../reader/file_opener.dart';
import '../recents/recents_screen.dart';
import '../cleaner/cleaner_screen.dart';
import '../search/search_screen.dart';
import '../tools/trash_screen.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_logo.dart';
import '../../shared/widgets/nexa_ui.dart';
import 'destination_picker.dart';
import 'category_screen.dart';
import 'file_actions.dart';
import 'file_tiles.dart';
import 'file_operation_service.dart';
import 'file_rules.dart';
import 'files_controller.dart';
import '../operations/operations_controller.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import '../../core/trash/trash_service.dart';
import '../../core/platform/providers.dart';
import '../../shared/formatters.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  bool searching = false;
  late final AppLifecycleListener _lifecycle;
  List<StorageEntry>? _metadataFor;
  Future<Map<String, LibraryRecord>>? _metadata;

  @override
  void initState() {
    super.initState();
    // Items older than 30 days leave the trash for good.
    unawaited(
      TrashService(
        ref.read(storageRepositoryProvider),
      ).purgeOlderThan(const Duration(days: 30)).catchError((_) => 0),
    );
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final state = ref.read(filesControllerProvider);
        if (!state.browsing) {
          ref.read(filesControllerProvider.notifier).loadRoots();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filesControllerProvider),
        controller = ref.read(filesControllerProvider.notifier);
    return Scaffold(
      appBar: state.browsing || state.selecting
          ? _appBar(state, controller)
          : null,
      body: Column(
        children: [
          if (state.browsing && !state.selecting)
            _Breadcrumb(path: state.path, onTap: controller.goTo),
          if (state.failure != null)
            MaterialBanner(
              content: Text(state.failure!.userMessage),
              actions: [
                TextButton(
                  onPressed: controller.refresh,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          Expanded(
            child: state.loading
                ? state.browsing
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            _homeHeader(),
                            const Expanded(
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        )
                : state.browsing
                ? _folder(state, controller)
                : _home(state, controller),
          ),
        ],
      ),
      floatingActionButton: state.browsing && !state.selecting
          ? Padding(
              // The shell's floating dock (and mini player) cover the bottom
              // of this nested scaffold: lift the button above them.
              padding: EdgeInsets.only(
                bottom:
                    (MediaQuery.paddingOf(context).bottom -
                            MediaQuery.viewPaddingOf(context).bottom)
                        .clamp(0, double.infinity),
              ),
              child: FloatingActionButton(
                onPressed: () => _createFolder(controller),
                tooltip: 'Nouveau dossier',
                child: const Icon(Icons.create_new_folder_rounded),
              ),
            )
          : null,
      bottomNavigationBar: state.selecting
          ? _selectionBar(state, controller)
          : null,
    );
  }

  Widget _continueReading() {
    final items = ref.watch(continueReadingProvider).valueOrNull;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final item = items.first, s = context.surfaces, theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: InkWell(
          onTap: () => RecentsScreen.openItem(
            context,
            ref,
            RecentRecord(
              id: item.id,
              uri: item.uri,
              name: item.name,
              format: item.format,
              openedAt: item.updatedAt,
              mime: item.mime,
              size: item.size,
              coverKey: item.coverKey,
              fraction: item.fraction,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  height: 68,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.coverKey == null
                        ? ColoredBox(
                            color: s.cardAlt,
                            child: Icon(Icons.auto_stories, color: accent),
                          )
                        : Image.file(
                            File(item.coverKey!),
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: s.cardAlt,
                              child: Icon(Icons.auto_stories, color: accent),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REPRENDRE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: item.fraction.clamp(0, 1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(item.fraction * 100).round()} %',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: s.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accent,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: AppTheme.onColor(accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(
    FileManagerState state,
    FilesController controller,
  ) {
    if (state.selecting) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Annuler la sélection',
          onPressed: controller.clearSelection,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(
          '${state.selected.length} sélectionné${state.selected.length > 1 ? 's' : ''}',
        ),
        actions: [
          IconButton(
            tooltip: 'Tout sélectionner',
            onPressed: controller.selectAll,
            icon: const Icon(Icons.select_all_rounded),
          ),
          IconButton(
            tooltip: 'Plus',
            onPressed: () => _selectionMenu(controller),
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      );
    }
    return AppBar(
      leading: IconButton(
        tooltip: 'Retour',
        onPressed: controller.goBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      titleSpacing: 0,
      title: searching
          ? TextField(
              autofocus: true,
              onChanged: controller.search,
              decoration: const InputDecoration(
                hintText: 'Rechercher dans ce dossier',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            )
          : Text(state.current!.displayName),
      actions: [
        IconButton(
          tooltip: searching ? 'Fermer la recherche' : 'Rechercher',
          onPressed: () {
            if (searching) controller.search('');
            setState(() => searching = !searching);
          },
          icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
        ),
        if (!searching) ...[
          IconButton(
            tooltip: state.viewMode == FileViewMode.list
                ? 'Afficher en grille'
                : 'Afficher en liste',
            onPressed: () => controller.setViewMode(
              state.viewMode == FileViewMode.list
                  ? FileViewMode.grid
                  : FileViewMode.list,
            ),
            icon: Icon(
              state.viewMode == FileViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_agenda_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Trier : ${_sortLabel(state.sort)}',
            onPressed: () => _sortSheet(state, controller),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => _menu(v, state, controller),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'folder',
                child: ListTile(
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('Nouveau dossier'),
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('Actualiser'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(width: 4),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 5 || hour >= 18 ? 'Bonsoir' : 'Bonjour';
  }

  Widget _homeHeader() => SafeArea(
    bottom: false,
    child: Column(
      children: [
        PageHeader(
          eyebrow: _greeting(),
          title: const _Wordmark(),
          actions: [
            RoundIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Paramètres',
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: _SearchLauncher(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _home(FileManagerState state, FilesController controller) {
    final header = _homeHeader();
    if (state.hasAccess == false) {
      return Column(
        children: [
          header,
          Expanded(
            child: EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'Autorisez l’accès à vos fichiers',
              message:
                  'NexaFiles a besoin de l’accès à tous les fichiers pour parcourir votre stockage comme un gestionnaire de fichiers. Tout reste sur votre appareil.',
              action: FilledButton.icon(
                onPressed: controller.requestAccess,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Autoriser l’accès'),
              ),
            ),
          ),
        ],
      );
    }
    final stats = ref.watch(categoryStatsProvider).valueOrNull ?? const {};
    final primary =
        state.roots.where((r) => r.primary).firstOrNull ??
        state.roots.firstOrNull;
    final storage = <Widget>[
      if (primary != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _StorageHero(
            root: primary,
            onTap: () => controller.openRoot(primary),
          ),
        ),
      for (final root in state.roots.where((r) => r != primary))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _LocationCard(
            root: root,
            onTap: () => controller.openRoot(root),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            leading: IconBubble(
              icon: Icons.cleaning_services_rounded,
              color: AppColors.image,
              size: 42,
            ),
            title: const Text('Libérer de l’espace'),
            subtitle: const Text(
              'Gros fichiers, doublons, APK, dossiers vides',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CleanerScreen()),
            ),
          ),
        ),
      ),
      _continueReading(),
    ];
    final browse = <Widget>[
      const SectionTitle('Catégories'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .78,
          children: [
            for (final category in categories)
              _CategoryTile(
                icon: category.icon,
                color: category.color,
                label: category.label,
                count: stats[category.key]?.count,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryScreen(category: category),
                  ),
                ),
              ),
            _CategoryTile(
              icon: Icons.delete_outline_rounded,
              color: context.surfaces.muted,
              label: 'Corbeille',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrashScreen()),
              ),
            ),
          ],
        ),
      ),
      if (state.quickFolders.isNotEmpty) ...[
        const SectionTitle('Accès rapides'),
        _QuickRow(
          children: [
            for (final folder in state.quickFolders)
              _QuickAccess(
                icon: _quickIcon(folder.folderName).$1,
                label: folder.label,
                color: _quickIcon(folder.folderName).$2,
                onTap: () => controller.openDirectory(folder.entry),
              ),
          ],
        ),
      ],
      if (state.favorites.isNotEmpty) ...[
        const SectionTitle('Favoris'),
        _QuickRow(
          children: [
            for (final folder in state.favorites)
              _QuickAccess(
                icon: Icons.star_rounded,
                label: folder.displayName,
                color: AppColors.folder,
                onTap: () => controller.openDirectory(folder),
              ),
          ],
        ),
      ],
    ];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(categoryStatsProvider);
        await controller.loadRoots();
      },
      // Landscape / tablets: storage on the left, browsing on the right,
      // instead of one stretched column.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return SafeArea(
            top: false,
            bottom: false,
            child: ListView(
              padding: EdgeInsets.only(bottom: dockInset(context)),
              children: [
                header,
                if (!wide) ...[
                  ...storage,
                  ...browse,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: Column(children: storage)),
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: browse,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  (IconData, Color) _quickIcon(String folderName) => switch (folderName) {
    'Download' => (Icons.download_rounded, AppColors.document),
    'Documents' => (Icons.description_rounded, AppColors.document),
    'DCIM' => (Icons.photo_camera_rounded, AppColors.image),
    'Pictures' => (Icons.image_rounded, AppColors.image),
    'Music' => (Icons.music_note_rounded, AppColors.audio),
    'Movies' => (Icons.movie_rounded, AppColors.video),
    _ => (Icons.folder_rounded, AppColors.folder),
  };

  Widget _folder(FileManagerState state, FilesController controller) {
    final entries = state.visibleEntries;
    if (entries.isEmpty) {
      return EmptyState(
        icon: state.query.isEmpty ? Icons.folder_open : Icons.search_off,
        title: state.query.isEmpty
            ? 'Ce dossier est vide.'
            : 'Aucun fichier trouvé.',
        message: state.query.isEmpty
            ? 'Créez un dossier ou actualisez le contenu.'
            : 'Essayez un autre nom.',
      );
    }
    void select(StorageEntry e) {
      HapticFeedback.selectionClick();
      controller.toggleSelection(e);
    }

    // Queried once per listing, not on every rebuild (selection, search…).
    if (!identical(_metadataFor, state.entries)) {
      _metadataFor = state.entries;
      _metadata = ref
          .read(databaseProvider)
          .libraryItemsByUris(
            state.entries
                .where((e) => e.kind == StorageEntryKind.file)
                .map((e) => '${e.uri}'),
          );
    }
    return FutureBuilder<Map<String, LibraryRecord>>(
      future: _metadata,
      initialData: const {},
      builder: (_, snapshot) {
        final metadata = snapshot.data ?? const {};
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: state.viewMode == FileViewMode.list
              ? ListView.builder(
                  padding: EdgeInsets.only(
                    top: 4,
                    bottom: dockInset(context) + 64,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => FileTile(
                    entry: entries[i],
                    item: metadata['${entries[i].uri}'],
                    selected: state.selected.contains(entries[i].uri),
                    favorite: state.isFavorite(entries[i].uri),
                    onTap: () => _tap(entries[i], state, controller),
                    onLongPress: () => select(entries[i]),
                    onMenu: (v) => _entryAction(v, entries[i], controller),
                  ),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    dockInset(context) + 64,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: .78,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => FileGridTile(
                    entry: entries[i],
                    item: metadata['${entries[i].uri}'],
                    selected: state.selected.contains(entries[i].uri),
                    onTap: () => _tap(entries[i], state, controller),
                    onLongPress: () => select(entries[i]),
                  ),
                ),
        );
      },
    );
  }

  /// Floating ink bar replacing the dock while items are selected.
  Widget _selectionBar(FileManagerState state, FilesController controller) {
    final s = context.surfaces;
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: s.canvas, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: s.canvas.withValues(alpha: .85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: s.ink,
        elevation: 8,
        shadowColor: Colors.black45,
        shape: const StadiumBorder(),
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                action(
                  Icons.copy_rounded,
                  'Copier',
                  () => _transfer(controller, false),
                ),
                action(
                  Icons.drive_file_move_rounded,
                  'Déplacer',
                  () => _transfer(controller, true),
                ),
                action(
                  Icons.ios_share_rounded,
                  'Partager',
                  () => _share(controller),
                ),
                action(
                  Icons.delete_outline_rounded,
                  'Supprimer',
                  () => _delete(controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tap(
    StorageEntry entry,
    FileManagerState state,
    FilesController controller,
  ) async {
    if (state.selecting) {
      controller.toggleSelection(entry);
      return;
    }
    if (entry.kind == StorageEntryKind.directory) {
      await controller.openFolder(entry);
      return;
    }
    try {
      await openFile(context, ref, entry, siblings: state.visibleEntries);
    } catch (e) {
      _error(e);
    }
  }

  void _menu(String value, FileManagerState state, FilesController controller) {
    if (value == 'folder') _createFolder(controller);
    if (value == 'view') {
      controller.setViewMode(
        state.viewMode == FileViewMode.list
            ? FileViewMode.grid
            : FileViewMode.list,
      );
    }
    if (value == 'sort') _sortSheet(state, controller);
    if (value == 'refresh') controller.refresh();
  }

  Future<void> _createFolder(FilesController controller) async {
    final value = await _nameDialog('Nouveau dossier', 'Nom du dossier');
    if (value == null) return;
    try {
      await controller.createFolder(value);
      _message('Dossier créé');
    } catch (e) {
      _error(e);
    }
  }

  Future<String?> _nameDialog(String title, String initial) async {
    final input = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  FileActions _actions(FilesController controller) => FileActions(
    context,
    ref,
    onChanged: () async {
      await controller.refresh();
      controller.clearSelection();
    },
  );

  void _entryAction(
    String action,
    StorageEntry entry,
    FilesController controller,
  ) {
    if (action == 'favorite') {
      controller.toggleFavorite(entry);
      return;
    }
    _actions(controller).handle(action, entry);
  }

  Future<void> _delete(FilesController controller) =>
      _actions(controller).delete(controller.selectedEntries);

  Future<void> _share(FilesController controller) =>
      _actions(controller).share(controller.selectedEntries);

  Future<void> _transfer(FilesController controller, bool move) async {
    final sources = controller.selectedEntries;
    if (sources.isEmpty) return;
    final target = await Navigator.push<Uri>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationPicker(
          storage: controller.storage,
          roots: ref.read(filesControllerProvider).roots,
        ),
      ),
    );
    if (target == null) return;
    final policy = await _conflictDialog();
    if (policy == null) return;
    final count = sources.length;
    ref
        .read(operationsProvider)
        .start(
          kind: move ? OperationKind.move : OperationKind.copy,
          title:
              '${move ? 'Déplacement' : 'Copie'} de '
              '${count == 1 ? '« ${sources.first.displayName} »' : '$count éléments'}',
          destination: target,
          run: (token) => FileOperationService(controller.storage)
              .transfer(
                sources: sources,
                destination: target,
                move: move,
                conflict: policy,
                cancellation: token,
              )
              .map(
                (p) => OperationProgress(
                  done: p.completed,
                  total: p.total,
                  current: p.currentName,
                  finished: p.done,
                ),
              ),
          onDone: controller.refresh,
        );
    controller.clearSelection();
  }

  Future<ConflictPolicy?> _conflictDialog() => showDialog<ConflictPolicy>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('En cas de conflit'),
      children: [
        for (final item in const [
          (ConflictPolicy.keepBoth, 'Conserver les deux'),
          (ConflictPolicy.replace, 'Remplacer'),
          (ConflictPolicy.skip, 'Ignorer'),
          (ConflictPolicy.cancel, 'Annuler l’opération'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, item.$1),
            child: Text(item.$2),
          ),
      ],
    ),
  );
  void _selectionMenu(FilesController controller) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Compresser…'),
              onTap: () {
                Navigator.pop(context);
                _actions(controller).compress(controller.selectedEntries);
              },
            ),
            if (controller.selectedEntries.length == 1 &&
                isExtractable(controller.selectedEntries.first))
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Extraire dans un dossier'),
                onTap: () {
                  Navigator.pop(context);
                  _actions(
                    controller,
                  ).handle('extract_folder', controller.selectedEntries.first);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Informations'),
              enabled: controller.selectedEntries.length == 1,
              onTap: () {
                Navigator.pop(context);
                showFileInfo(context, controller.selectedEntries.first);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Ouvrir avec…'),
              enabled:
                  controller.selectedEntries.length == 1 &&
                  controller.selectedEntries.first.kind ==
                      StorageEntryKind.file,
              onTap: () {
                Navigator.pop(context);
                controller.storage.openExternal(
                  controller.selectedEntries.first.uri,
                  mimeType: controller.selectedEntries.first.mimeType,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sortSheet(FileManagerState state, FilesController controller) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<FileSort>(
              groupValue: state.sort,
              onChanged: (v) {
                controller.setSort(v!);
                Navigator.pop(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final value in FileSort.values)
                    RadioListTile<FileSort>(
                      value: value,
                      title: Text(_sortLabel(value)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(
                state.direction == SortDirection.ascending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
              ),
              title: Text(
                state.direction == SortDirection.ascending
                    ? 'Croissant'
                    : 'Décroissant',
              ),
              onTap: () {
                controller.toggleDirection();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(FileSort value) => switch (value) {
    FileSort.name => 'Nom',
    FileSort.date => 'Date',
    FileSort.size => 'Taille',
    FileSort.type => 'Type',
  };
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _error(Object error) => _message(
    error.toString().replaceFirst(RegExp(r'^\w+(Failure|Exception): '), ''),
  );
}

/// "NexaFiles" with the accent on the second half.
class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const NexaLogo(size: 34),
      const SizedBox(width: 10),
      Flexible(
        child: Text.rich(
          TextSpan(
            text: 'Nexa',
            children: [
              TextSpan(
                text: 'Files',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.onTap});
  final List<NavigationNode> path;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces, accent = context.accent;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: false,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        itemCount: path.length,
        separatorBuilder: (_, _) =>
            Icon(Icons.chevron_right_rounded, size: 18, color: s.muted),
        itemBuilder: (_, i) {
          final last = i == path.length - 1;
          return Material(
            color: last ? accent.withValues(alpha: .14) : s.card,
            shape: StadiumBorder(
              side: BorderSide(color: last ? Colors.transparent : s.line),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0) ...[
                        Icon(
                          Icons.smartphone_rounded,
                          size: 15,
                          color: last ? accent : s.muted,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        path[i].entry.displayName,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppFonts.body,
                          fontSize: 13,
                          fontWeight: last ? FontWeight.w800 : FontWeight.w600,
                          color: last ? accent : s.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The primary volume, shown as a bold accent card with a usage ring.
class _StorageHero extends StatelessWidget {
  const _StorageHero({required this.root, required this.onTap});
  final RootLocation root;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    final total = root.totalBytes, free = root.freeBytes;
    final used = total != null && free != null ? total - free : null;
    final fraction = used != null && total! > 0 ? used / total : null;
    final on = AppTheme.onColor(accent);
    final hsl = HSLColor.fromColor(accent);
    final deep = hsl
        .withLightness((hsl.lightness - .18).clamp(0, 1))
        .withHue((hsl.hue + 18) % 360)
        .toColor();
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, deep],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Decorative rings.
              Positioned(
                right: -40,
                top: -50,
                child: _Ring(size: 180, color: on.withValues(alpha: .08)),
              ),
              Positioned(
                left: -30,
                bottom: -70,
                child: _Ring(size: 140, color: on.withValues(alpha: .06)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                root.removable
                                    ? Icons.sd_card_rounded
                                    : Icons.smartphone_rounded,
                                size: 16,
                                color: on.withValues(alpha: .85),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  root.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: on.withValues(alpha: .9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            fraction == null
                                ? 'Parcourir'
                                : '${(fraction * 100).round()} %',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: on,
                              fontSize: 42,
                              height: 1,
                            ),
                          ),
                          if (fraction != null) ...[
                            Text(
                              'utilisés',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: on.withValues(alpha: .8),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: on.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                '${formatBytes(free)} libres sur ${formatBytes(total)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: on,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(
                        painter: _GaugePainter(
                          value: fraction ?? 0,
                          track: on.withValues(alpha: .18),
                          color: on,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.arrow_outward_rounded,
                            color: on,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 22),
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.track,
    required this.color,
  });
  final double value;
  final Color track, color;
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    const start = math.pi * .75, sweep = math.pi * 1.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * value.clamp(0, 1),
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Secondary volumes (SD card, USB…).
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.root, required this.onTap});
  final RootLocation root;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final total = root.totalBytes, free = root.freeBytes;
    final used = total != null && free != null ? total - free : null;
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBubble(
                icon: root.removable
                    ? Icons.sd_card_rounded
                    : Icons.smartphone_rounded,
                color: theme.colorScheme.primary,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      root.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (used != null && total! > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: used / total),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatBytes(free)} disponibles sur ${formatBytes(total)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.surfaces.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.count,
  });
  final IconData icon;
  final Color color;
  final String label;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconBubble(icon: icon, color: color, size: 42),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                count == null ? ' ' : '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: context.surfaces.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 104,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, i) => children[i],
    ),
  );
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: SizedBox(
      width: 112,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBubble(icon: icon, color: color, size: 38),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Looks like a search field; opens the global search.
class _SearchLauncher extends StatelessWidget {
  const _SearchLauncher({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Semantics(
      button: true,
      label: 'Rechercher dans tout le stockage',
      excludeSemantics: true,
      child: Material(
        color: s.cardAlt,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search_rounded, color: s.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rechercher dans tout le stockage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontSize: 15,
                      color: s.muted,
                    ),
                  ),
                ),
                Icon(Icons.tune_rounded, color: s.muted, size: 20),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
