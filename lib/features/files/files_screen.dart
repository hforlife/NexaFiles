import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_provider.dart';
import '../../core/storage/storage_entry.dart';
import '../reader/file_opener.dart';
import '../recents/recents_screen.dart';
import '../../shared/widgets/empty_state.dart';
import 'destination_picker.dart';
import 'category_screen.dart';
import 'file_tiles.dart';
import 'file_operation_service.dart';
import 'file_rules.dart';
import 'files_controller.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import '../../core/trash/trash_service.dart';
import '../../shared/formatters.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  bool searching = false;
  CancellationToken? operationToken;
  late final AppLifecycleListener _lifecycle;
  List<StorageEntry>? _metadataFor;
  Future<Map<String, LibraryRecord>>? _metadata;

  @override
  void initState() {
    super.initState();
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
      appBar: _appBar(state, controller),
      body: Column(
        children: [
          if (state.browsing)
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
          if (!state.browsing) _continueReading(),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.browsing
                ? _folder(state, controller)
                : _roots(state, controller),
          ),
        ],
      ),
      floatingActionButton: state.browsing && !state.selecting
          ? FloatingActionButton(
              onPressed: () => _createFolder(controller),
              tooltip: 'Nouveau dossier',
              child: const Icon(Icons.create_new_folder_outlined),
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
    final item = items.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: ListTile(
          leading: SizedBox(
            width: 52,
            height: 64,
            child: item.coverKey == null
                ? const Icon(Icons.auto_stories, size: 38)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(item.coverKey!),
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.auto_stories, size: 38),
                    ),
                  ),
          ),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: item.fraction.clamp(0, 1)),
              Text('${(item.fraction * 100).round()} %'),
            ],
          ),
          trailing: const Text('Continuer'),
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
          onPressed: controller.clearSelection,
          icon: const Icon(Icons.close),
        ),
        title: Text(
          '${state.selected.length} sélectionné${state.selected.length > 1 ? 's' : ''}',
        ),
        actions: [
          IconButton(
            tooltip: 'Tout sélectionner',
            onPressed: controller.selectAll,
            icon: const Icon(Icons.select_all),
          ),
          IconButton(
            tooltip: 'Plus',
            onPressed: () => _selectionMenu(controller),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      );
    }
    return AppBar(
      leading: state.browsing
          ? IconButton(
              tooltip: 'Retour',
              onPressed: controller.goBack,
              icon: const Icon(Icons.arrow_back),
            )
          : null,
      title: searching
          ? TextField(
              autofocus: true,
              onChanged: controller.search,
              decoration: const InputDecoration(
                hintText: 'Rechercher dans ce dossier',
                border: InputBorder.none,
              ),
            )
          : Text(state.browsing ? state.current!.displayName : 'NexaFiles'),
      actions: [
        if (state.browsing)
          IconButton(
            tooltip: 'Rechercher',
            onPressed: () => setState(() => searching = !searching),
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
        if (state.browsing)
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
                  : Icons.view_list_rounded,
            ),
          ),
        if (state.browsing)
          IconButton(
            tooltip: 'Trier : ${_sortLabel(state.sort)}',
            onPressed: () => _sortSheet(state, controller),
            icon: Badge(
              label: Icon(
                state.direction == SortDirection.ascending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 10,
              ),
              child: const Icon(Icons.sort),
            ),
          ),
        if (state.browsing)
          PopupMenuButton<String>(
            onSelected: (v) => _menu(v, state, controller),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'folder',
                child: Text('Nouveau dossier'),
              ),
              const PopupMenuItem(value: 'refresh', child: Text('Actualiser')),
            ],
          ),
      ],
    );
  }

  Widget _roots(FileManagerState state, FilesController controller) {
    if (state.hasAccess == false) {
      return EmptyState(
        icon: Icons.folder_open,
        title: 'Autorisez l’accès à vos fichiers',
        message:
            'NexaFiles a besoin de l’accès à tous les fichiers pour parcourir votre stockage comme un gestionnaire de fichiers. Tout reste sur votre appareil.',
        action: FilledButton.icon(
          onPressed: controller.requestAccess,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Autoriser l’accès'),
        ),
      );
    }
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final stats = ref.watch(categoryStatsProvider).valueOrNull ?? const {};
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(categoryStatsProvider);
        await controller.loadRoots();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text('Stockage', style: titleStyle),
          const SizedBox(height: 12),
          for (final root in state.roots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _LocationCard(
                root: root,
                onTap: () => controller.openRoot(root),
              ),
            ),
          const SizedBox(height: 16),
          Text('Catégories', style: titleStyle),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .82,
            children: [
              for (final category in categories)
                _CategoryTile(
                  category: category,
                  count: stats[category.key]?.count,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryScreen(category: category),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Accès rapides', style: titleStyle),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
          if (state.favorites.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('Favoris', style: titleStyle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final folder in state.favorites)
                  _QuickAccess(
                    icon: Icons.star_rounded,
                    label: folder.displayName,
                    color: Colors.amber.shade800,
                    onTap: () => controller.openDirectory(folder),
                  ),
              ],
            ),
          ],
        ],
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
                  padding: const EdgeInsets.only(bottom: 88),
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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
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

  Widget _selectionBar(FileManagerState state, FilesController controller) =>
      SafeArea(
        child: NavigationBar(
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.copy_outlined),
              label: 'Copier',
            ),
            NavigationDestination(
              icon: Icon(Icons.drive_file_move_outlined),
              label: 'Déplacer',
            ),
            NavigationDestination(
              icon: Icon(Icons.share_outlined),
              label: 'Partager',
            ),
            NavigationDestination(
              icon: Icon(Icons.delete_outline),
              label: 'Supprimer',
            ),
          ],
          onDestinationSelected: (i) {
            if (i == 0) _transfer(controller, false);
            if (i == 1) _transfer(controller, true);
            if (i == 2) _share(controller);
            if (i == 3) _delete(controller);
          },
        ),
      );
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

  Future<void> _rename(StorageEntry entry, FilesController controller) async {
    final value = await _nameDialog('Renommer', entry.displayName);
    if (value == null || value == entry.displayName) return;
    try {
      await controller.rename(entry, value);
      _message('Élément renommé');
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

  void _entryAction(
    String action,
    StorageEntry entry,
    FilesController controller,
  ) {
    if (action == 'rename') _rename(entry, controller);
    if (action == 'favorite') controller.toggleFavorite(entry);
    if (action == 'info') _info(entry);
    if (action == 'open') {
      controller.storage
          .openExternal(entry.uri, mimeType: entry.mimeType)
          .catchError(_error);
    }
    if (action == 'delete') {
      _delete(controller, [entry]);
    }
  }

  /// Trashes [only] when given (single-entry menu), else the visible selection.
  Future<void> _delete(
    FilesController controller, [
    List<StorageEntry>? only,
  ]) async {
    final entries = only ?? controller.selectedEntries,
        state = ref.read(filesControllerProvider);
    if (entries.isEmpty || state.current == null || state.path.isEmpty) return;
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              entries.length == 1
                  ? 'Mettre « ${entries.first.displayName} » à la corbeille ?'
                  : 'Mettre ${entries.length} éléments à la corbeille ?',
            ),
            content: const Text(
              'Les fichiers compatibles pourront être restaurés depuis Outils > Corbeille.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Mettre à la corbeille'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes) return;
    final trash = TrashService(controller.storage), failed = <StorageEntry>[];
    var moved = 0;
    for (final entry in entries) {
      if (await trash.moveToTrash(
        entry,
        state.current!.uri,
        state.path.first.entry.uri,
      )) {
        moved++;
      } else {
        failed.add(entry);
      }
    }
    if (failed.isNotEmpty && mounted) {
      final permanent =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('${failed.length} élément(s) non déplaçable(s)'),
              content: const Text(
                'Ces éléments ne peuvent pas être mis dans la corbeille. Voulez-vous les supprimer définitivement ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Conserver'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Supprimer définitivement'),
                ),
              ],
            ),
          ) ??
          false;
      if (permanent) {
        final result = await FileOperationService(
          controller.storage,
        ).deleteAll(failed);
        moved += result.succeeded;
      }
    }
    await controller.refresh();
    controller.clearSelection();
    _message('$moved élément(s) traité(s)');
  }

  Future<void> _share(FilesController controller) async {
    final entries = controller.selectedEntries
        .where((e) => e.kind == StorageEntryKind.file)
        .toList();
    if (entries.isEmpty) {
      _error('Sélectionnez au moins un fichier.');
      return;
    }
    try {
      await controller.storage.share(
        entries.map((e) => e.uri).toList(),
        mimeType: entries.length == 1 ? entries.first.mimeType : null,
      );
      controller.clearSelection();
    } catch (e) {
      _error(e);
    }
  }

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
    operationToken = CancellationToken();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _OperationDialog(
        stream: FileOperationService(controller.storage).transfer(
          sources: sources,
          destination: target,
          move: move,
          conflict: policy,
          cancellation: operationToken!,
        ),
        onCancel: operationToken!.cancel,
        onDone: () {
          Navigator.pop(dialogContext);
          controller.refresh();
        },
      ),
    );
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
              leading: const Icon(Icons.info_outline),
              title: const Text('Informations'),
              enabled: controller.selectedEntries.length == 1,
              onTap: () {
                Navigator.pop(context);
                _info(controller.selectedEntries.first);
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

  void _info(StorageEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _detail(
                'Type',
                entry.kind == StorageEntryKind.directory
                    ? 'Dossier'
                    : entry.mimeType ?? 'Fichier inconnu',
              ),
              _detail(
                'Taille',
                entry.kind == StorageEntryKind.directory
                    ? 'Non calculée'
                    : formatBytes(entry.size),
              ),
              _detail(
                'Modification',
                entry.modifiedAt?.toLocal().toString() ?? 'Inconnue',
              ),
              const ExpansionTile(
                title: Text('Informations avancées'),
                children: [],
              ),
              SelectableText(
                '${entry.uri}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
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

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.onTap});
  final List<NavigationNode> path;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: path.length,
      separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 18),
      itemBuilder: (_, i) => TextButton(
        onPressed: () => onTap(i),
        child: Text(path[i].entry.displayName, maxLines: 1),
      ),
    ),
  );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.root, required this.onTap});
  final RootLocation root;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final total = root.totalBytes, free = root.freeBytes;
    final used = total != null && free != null ? total - free : null;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  root.removable
                      ? Icons.sd_card_rounded
                      : Icons.phone_android_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      root.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (used != null && total! > 0) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: used / total),
                      const SizedBox(height: 6),
                      Text(
                        '${formatBytes(used)} utilisés sur ${formatBytes(total)} • ${formatBytes(free)} libres',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });
  final CategoryInfo category;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: category.color.withValues(
                alpha: theme.brightness == Brightness.light ? .14 : .24,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(category.icon, color: category.color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            category.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          Text(
            count == null ? ' ' : '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
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
    child: ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, color: color),
      label: Text(label),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    ),
  );
}

class _OperationDialog extends StatefulWidget {
  const _OperationDialog({
    required this.stream,
    required this.onCancel,
    required this.onDone,
  });
  final Stream<FileOperationProgress> stream;
  final VoidCallback onCancel, onDone;
  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  FileOperationProgress? progress;
  Object? error;
  StreamSubscription? subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.stream.listen(
      (p) {
        if (p.done) {
          widget.onDone();
        } else if (mounted) {
          setState(() => progress = p);
        }
      },
      onError: (e) {
        if (mounted) setState(() => error = e);
      },
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      progress?.kind == FileOperationKind.move ? 'Déplacement' : 'Copie',
    ),
    content: error != null
        ? Text('$error')
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: progress?.fraction),
              const SizedBox(height: 12),
              Text(progress?.currentName ?? 'Préparation…'),
            ],
          ),
    actions: [
      TextButton(
        onPressed: () {
          widget.onCancel();
          Navigator.pop(context);
        },
        child: const Text('Annuler'),
      ),
    ],
  );
}
