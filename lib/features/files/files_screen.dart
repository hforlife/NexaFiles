import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/app_router.dart';
import '../../core/database/database_provider.dart';
import '../../core/formats/format_detector.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/readers/document_adapters.dart';
import '../../core/readers/media_adapters.dart';
import '../reader/comic_reader_screen.dart';
import '../reader/document_reader_screens.dart';
import '../reader/media_reader_screens.dart';
import '../reader/document_cover_service.dart';
import '../reader/comic_cover_service.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/formats/detected_format.dart';
import '../../core/comics/comic_page_source.dart';
import '../archives/archive_browser_screen.dart';
import '../recents/recents_screen.dart';
import '../../shared/widgets/empty_state.dart';
import 'destination_picker.dart';
import 'file_operation_service.dart';
import 'file_rules.dart';
import 'files_controller.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import '../../core/cache/file_preview_service.dart';
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
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filesControllerProvider),
        controller = ref.read(filesControllerProvider.notifier);
    return WillPopScope(
        onWillPop: () async => !(await controller.goBack()),
        child: Scaffold(
            appBar: _appBar(state, controller),
            body: Column(children: [
              if (state.browsing)
                _Breadcrumb(
                    path: state.path,
                    onTap: (index) async {
                      while (ref.read(filesControllerProvider).path.length >
                          index + 1) {
                        await controller.goBack();
                      }
                    }),
              if (state.failure != null)
                MaterialBanner(
                    content: Text(state.failure!.userMessage),
                    actions: [
                      TextButton(
                          onPressed: controller.refresh,
                          child: const Text('Réessayer'))
                    ]),
              if (!state.browsing) _continueReading(),
              Expanded(
                  child: state.loading
                      ? const Center(child: CircularProgressIndicator())
                      : state.browsing
                          ? _folder(state, controller)
                          : _roots(state, controller))
            ]),
            floatingActionButton: state.browsing && !state.selecting
                ? FloatingActionButton(
                    onPressed: () => _createFolder(controller),
                    tooltip: 'Nouveau dossier',
                    child: const Icon(Icons.create_new_folder_outlined))
                : null,
            bottomNavigationBar:
                state.selecting ? _selectionBar(state, controller) : null));
  }

  Widget _continueReading() => FutureBuilder<List<ContinueReadingRecord>>(
      future: ref.read(databaseProvider).continueReading(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final item = snapshot.data!.first,
            cover = item.coverKey == null ? null : File(item.coverKey!);
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Card(
                child: ListTile(
                    leading: SizedBox(
                        width: 52,
                        height: 64,
                        child: cover != null && cover.existsSync()
                            ? Image.file(cover,
                                fit: BoxFit.cover, cacheWidth: 160)
                            : const Icon(Icons.auto_stories, size: 38)),
                    title: Text(item.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                              value: item.fraction.clamp(0, 1)),
                          Text('${(item.fraction * 100).round()} %')
                        ]),
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
                            fraction: item.fraction)))));
      });
  PreferredSizeWidget _appBar(
      FileManagerState state, FilesController controller) {
    if (state.selecting) {
      return AppBar(
          leading: IconButton(
              onPressed: controller.clearSelection,
              icon: const Icon(Icons.close)),
          title: Text(
              '${state.selected.length} sélectionné${state.selected.length > 1 ? 's' : ''}'),
          actions: [
            IconButton(
                tooltip: 'Tout sélectionner',
                onPressed: controller.selectAll,
                icon: const Icon(Icons.select_all)),
            IconButton(
                tooltip: 'Plus',
                onPressed: () => _selectionMenu(controller),
                icon: const Icon(Icons.more_vert))
          ]);
    }
    return AppBar(
        leading: state.browsing
            ? IconButton(
                tooltip: 'Retour',
                onPressed: controller.goBack,
                icon: const Icon(Icons.arrow_back))
            : null,
        title: searching
            ? TextField(
                autofocus: true,
                onChanged: controller.search,
                decoration: const InputDecoration(
                    hintText: 'Rechercher dans ce dossier',
                    border: InputBorder.none))
            : Text(state.browsing ? state.current!.displayName : 'NexaFiles'),
        actions: [
          if (state.browsing)
            IconButton(
                tooltip: 'Rechercher',
                onPressed: () => setState(() => searching = !searching),
                icon: Icon(searching ? Icons.close : Icons.search)),
          if (state.browsing)
            IconButton(
                tooltip: state.viewMode == FileViewMode.list
                    ? 'Afficher en grille'
                    : 'Afficher en liste',
                onPressed: () => controller.setViewMode(
                    state.viewMode == FileViewMode.list
                        ? FileViewMode.grid
                        : FileViewMode.list),
                icon: Icon(state.viewMode == FileViewMode.list
                    ? Icons.grid_view_rounded
                    : Icons.view_list_rounded)),
          if (state.browsing)
            IconButton(
                tooltip: 'Trier : ${_sortLabel(state.sort)}',
                onPressed: () => _sortSheet(state, controller),
                icon: Badge(
                    label: Icon(
                        state.direction == SortDirection.ascending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 10),
                    child: const Icon(Icons.sort))),
          if (state.browsing)
            PopupMenuButton<String>(
                onSelected: (v) => _menu(v, state, controller),
                itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'folder', child: Text('Nouveau dossier')),
                      const PopupMenuItem(
                          value: 'refresh', child: Text('Actualiser'))
                    ])
        ]);
  }

  Widget _roots(FileManagerState state, FilesController controller) {
    if (state.roots.isEmpty) {
      return EmptyState(
          icon: Icons.folder_open,
          title: 'Vos fichiers, à votre façon',
          message:
              'Ajoutez un emplacement pour accéder rapidement à vos documents et lectures.',
          action: FilledButton.icon(
              onPressed: controller.addLocation,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un emplacement')));
    }
    final roots = [...state.roots]
      ..sort((a, b) => (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0));
    final favorite = roots.where((e) => e.favorite).toList();
    return RefreshIndicator(
        onRefresh: controller.loadRoots,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Row(children: [
                Expanded(
                    child: Text('Emplacements',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton.filledTonal(
                    tooltip: 'Ajouter',
                    onPressed: controller.addLocation,
                    icon: const Icon(Icons.add))
              ]),
              const SizedBox(height: 12),
              GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      childAspectRatio: 1.45,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12),
                  itemCount: roots.length,
                  itemBuilder: (_, i) {
                    final root = roots[i];
                    return _LocationCard(
                        root: root,
                        onTap: () => controller.openRoot(root),
                        onMenu: (v) {
                          if (v == 'favorite') controller.toggleFavorite(root);
                          if (v == 'remove') {
                            _confirmRemoveRoot(root, controller);
                          }
                          if (v == 'reauthorize') controller.addLocation();
                        });
                  }),
              const SizedBox(height: 28),
              Text('Accès rapides',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _QuickAccess(
                    icon: Icons.history_rounded,
                    label: 'Récents',
                    color: AppColors.reading,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.recents)),
                _QuickAccess(
                    icon: Icons.auto_stories_rounded,
                    label: 'Livres / BD',
                    color: AppColors.reading,
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.library)),
                for (final root in favorite)
                  _QuickAccess(
                      icon: Icons.star_rounded,
                      label: root.name,
                      color: Colors.amber.shade800,
                      onTap: () => controller.openRoot(root)),
                for (final root in roots.where((r) =>
                    RegExp(r'télécharg|download', caseSensitive: false)
                        .hasMatch(r.name)))
                  _QuickAccess(
                      icon: Icons.download_rounded,
                      label: 'Téléchargements',
                      color: Colors.blue,
                      onTap: () => controller.openRoot(root)),
                for (final root in roots.where((r) =>
                    RegExp(r'document', caseSensitive: false).hasMatch(r.name)))
                  _QuickAccess(
                      icon: Icons.description_rounded,
                      label: 'Documents',
                      color: Colors.indigo,
                      onTap: () => controller.openRoot(root)),
                for (final root in roots.where((r) =>
                    RegExp(r'image|dcim|photo', caseSensitive: false)
                        .hasMatch(r.name)))
                  _QuickAccess(
                      icon: Icons.image_rounded,
                      label: 'Images',
                      color: AppColors.image,
                      onTap: () => controller.openRoot(root))
              ])
            ]));
  }

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
              : 'Essayez un autre nom.');
    }
    void select(StorageEntry e) {
      HapticFeedback.selectionClick();
      controller.toggleSelection(e);
    }

    return FutureBuilder<Map<String, LibraryRecord>>(
        future: ref.read(databaseProvider).libraryItemsByUris(entries
            .where((e) => e.kind == StorageEntryKind.file)
            .map((e) => '${e.uri}')),
        initialData: const {},
        builder: (_, snapshot) {
          final metadata = snapshot.data ?? const {};
          return RefreshIndicator(
              onRefresh: controller.refresh,
              child: state.viewMode == FileViewMode.list
                  ? ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: entries.length,
                      itemBuilder: (_, i) => _FileTile(
                          entry: entries[i],
                          item: metadata['${entries[i].uri}'],
                          selected: state.selected.contains(entries[i].uri),
                          onTap: () => _tap(entries[i], state, controller),
                          onLongPress: () => select(entries[i]),
                          onMenu: (v) =>
                              _entryAction(v, entries[i], controller)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              childAspectRatio: .78,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8),
                      itemCount: entries.length,
                      itemBuilder: (_, i) => _FileGrid(
                          entry: entries[i],
                          item: metadata['${entries[i].uri}'],
                          selected: state.selected.contains(entries[i].uri),
                          onTap: () => _tap(entries[i], state, controller),
                          onLongPress: () => select(entries[i]))));
        });
  }

  Widget _selectionBar(FileManagerState state, FilesController controller) =>
      SafeArea(
          child: NavigationBar(
              destinations: const [
            NavigationDestination(
                icon: Icon(Icons.copy_outlined), label: 'Copier'),
            NavigationDestination(
                icon: Icon(Icons.drive_file_move_outlined), label: 'Déplacer'),
            NavigationDestination(
                icon: Icon(Icons.share_outlined), label: 'Partager'),
            NavigationDestination(
                icon: Icon(Icons.delete_outline), label: 'Supprimer')
          ],
              onDestinationSelected: (i) {
                if (i == 0) _transfer(controller, false);
                if (i == 1) _transfer(controller, true);
                if (i == 2) _share(controller);
                if (i == 3) _delete(controller);
              }));
  Future<void> _tap(StorageEntry entry, FileManagerState state,
      FilesController controller) async {
    if (state.selecting) {
      controller.toggleSelection(entry);
      return;
    }
    if (entry.kind == StorageEntryKind.directory) {
      await controller.openFolder(entry);
      return;
    }
    try {
      final watch = Stopwatch()..start(),
          source = controller.storage.sourceFor(entry),
          prefix = await controller.storage.readPrefix(entry.uri);
      var detected = FormatDetector().detect(
          prefix: prefix,
          mimeType: entry.mimeType,
          fileName: entry.displayName);
      final archives = ref.read(archiveRegistryProvider);
      if (detected.container != ContainerFormat.none &&
          detected.content == ContentKind.archive) {
        final archive = await archives.open(source, detected);
        final entries = await archive.listEntries();
        detected = FormatDetector().detect(
            prefix: prefix,
            mimeType: entry.mimeType,
            fileName: entry.displayName,
            archiveEntries: entries.map((e) => e.path));
        if (detected.content == ContentKind.archive) {
          if (mounted) {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ArchiveBrowserScreen(
                        name: entry.displayName,
                        session: archive,
                        storage: controller.storage,
                        roots: state.roots,
                        defaultDestination: state.current?.uri)));
          }
          return;
        }
        await archive.close();
      }
      assert(() {
        debugPrint(
            '[PERF] format detection/open routing = ${watch.elapsedMilliseconds} ms (${detected.content.name})');
        return true;
      }());
      if ({
        ContentKind.officeWord,
        ContentKind.officeSpreadsheet,
        ContentKind.officePresentation,
        ContentKind.apk
      }.contains(detected.content)) {
        await controller.storage.openExternal(entry.uri,
            mimeType: _externalMime(detected, entry.mimeType));
        return;
      }
      final adapter = ref.read(readerRegistryProvider).find(detected);
      if (adapter == null) {
        await controller.storage
            .openExternal(entry.uri, mimeType: entry.mimeType);
        return;
      }
      final session = await adapter.open(source, detected);
      await ref.read(databaseProvider).recordRecent(
          id: '${entry.uri}',
          uri: '${entry.uri}',
          name: entry.displayName,
          format: detected.content.name,
          mime: entry.mimeType,
          size: entry.size);
      ref.read(recentOpenEpochProvider.notifier).state++;
      if (!mounted) {
        await session.dispose();
        return;
      }
      final db = ref.read(databaseProvider),
          id = '${entry.uri}',
          covers = DocumentCoverService(CacheManager(), db);
      Widget screen;
      if (session is ComicReaderSession) {
        unawaited(ComicCoverService(CacheManager(), db)
            .ensureCover(id, session.pages));
        screen = ComicReaderScreen(
            session: session,
            database: db,
            itemId: id,
            title: entry.displayName);
      } else if (session is PdfReaderSession) {
        unawaited(covers.ensurePdf(id, session));
        screen = PdfReaderScreen(
            session: session,
            database: db,
            itemId: id,
            title: entry.displayName);
      } else if (session is EpubReaderSession) {
        unawaited(covers.ensureEpub(id, session));
        screen = EpubReaderScreen(session: session, database: db, itemId: id);
      } else if (session is TextReaderSession) {
        screen = TextReaderScreen(
            session: session,
            database: db,
            itemId: id,
            title: entry.displayName);
      } else if (session is ImageReaderSession) {
        final images = state.entries
            .where((e) =>
                e.kind == StorageEntryKind.file &&
                RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false)
                    .hasMatch(e.displayName))
            .toList()
          ..sort((a, b) => naturalCompare(a.displayName, b.displayName));
        screen = ImageReaderScreen(
            session: session,
            title: entry.displayName,
            images: images,
            storage: controller.storage,
            initialIndex: images
                .indexWhere((e) => e.uri == entry.uri)
                .clamp(0, images.length - 1));
      } else if (session is MediaReaderSession &&
          session.kind == ContentKind.audio) {
        screen = AudioReaderScreen(session: session, title: entry.displayName);
      } else if (session is MediaReaderSession) {
        screen = VideoReaderScreen(session: session, title: entry.displayName);
      } else {
        await session.dispose();
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    } catch (e) {
      _error(e);
    }
  }

  void _menu(String value, FileManagerState state, FilesController controller) {
    if (value == 'folder') _createFolder(controller);
    if (value == 'view') {
      controller.setViewMode(state.viewMode == FileViewMode.list
          ? FileViewMode.grid
          : FileViewMode.list);
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
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, input.text),
                      child: const Text('Valider'))
                ]));
  }

  void _entryAction(
      String action, StorageEntry entry, FilesController controller) {
    if (action == 'rename') _rename(entry, controller);
    if (action == 'info') _info(entry);
    if (action == 'open') {
      controller.storage
          .openExternal(entry.uri, mimeType: entry.mimeType)
          .catchError(_error);
    }
    if (action == 'delete') {
      controller.toggleSelection(entry);
      _delete(controller);
    }
  }

  Future<void> _delete(FilesController controller) async {
    final entries = controller.selectedEntries,
        state = ref.read(filesControllerProvider);
    if (entries.isEmpty || state.current == null || state.path.isEmpty) return;
    final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(entries.length == 1
                        ? 'Mettre « ${entries.first.displayName} » à la corbeille ?'
                        : 'Mettre ${entries.length} éléments à la corbeille ?'),
                    content: const Text(
                        'Les fichiers compatibles pourront être restaurés depuis Outils > Corbeille.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Mettre à la corbeille'))
                    ])) ??
        false;
    if (!yes) return;
    final trash = TrashService(controller.storage), failed = <StorageEntry>[];
    var moved = 0;
    for (final entry in entries) {
      if (await trash.moveToTrash(
          entry, state.current!.uri, state.path.first.entry.uri)) {
        moved++;
      } else {
        failed.add(entry);
      }
    }
    if (failed.isNotEmpty && mounted) {
      final permanent = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                      title:
                          Text('${failed.length} élément(s) non déplaçable(s)'),
                      content: const Text(
                          'Ces éléments ne peuvent pas être mis dans la corbeille. Voulez-vous les supprimer définitivement ?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Conserver')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Supprimer définitivement'))
                      ])) ??
          false;
      if (permanent) {
        final result =
            await FileOperationService(controller.storage).deleteAll(failed);
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
      await controller.storage.share(entries.map((e) => e.uri).toList(),
          mimeType: entries.length == 1 ? entries.first.mimeType : null);
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
                roots: ref.read(filesControllerProvider).roots)));
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
                cancellation: operationToken!),
            onCancel: operationToken!.cancel,
            onDone: () {
              Navigator.pop(dialogContext);
              controller.refresh();
            }));
  }

  Future<ConflictPolicy?> _conflictDialog() => showDialog<ConflictPolicy>(
      context: context,
      builder: (context) =>
          SimpleDialog(title: const Text('En cas de conflit'), children: [
            for (final item in const [
              (ConflictPolicy.keepBoth, 'Conserver les deux'),
              (ConflictPolicy.replace, 'Remplacer'),
              (ConflictPolicy.skip, 'Ignorer'),
              (ConflictPolicy.cancel, 'Annuler l’opération')
            ])
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item.$1),
                  child: Text(item.$2))
          ]));
  void _selectionMenu(FilesController controller) {
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Informations'),
                  enabled: controller.selectedEntries.length == 1,
                  onTap: () {
                    Navigator.pop(context);
                    _info(controller.selectedEntries.first);
                  }),
              ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Ouvrir avec…'),
                  enabled: controller.selectedEntries.length == 1 &&
                      controller.selectedEntries.first.kind ==
                          StorageEntryKind.file,
                  onTap: () {
                    Navigator.pop(context);
                    controller.storage.openExternal(
                        controller.selectedEntries.first.uri,
                        mimeType: controller.selectedEntries.first.mimeType);
                  })
            ])));
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
                      Text(entry.displayName,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      _detail(
                          'Type',
                          entry.kind == StorageEntryKind.directory
                              ? 'Dossier'
                              : entry.mimeType ?? 'Fichier inconnu'),
                      _detail(
                          'Taille',
                          entry.kind == StorageEntryKind.directory
                              ? 'Non calculée'
                              : formatBytes(entry.size)),
                      _detail('Modification',
                          entry.modifiedAt?.toLocal().toString() ?? 'Inconnue'),
                      const ExpansionTile(
                          title: Text('Informations avancées'), children: []),
                      SelectableText('${entry.uri}',
                          style: Theme.of(context).textTheme.bodySmall)
                    ]))));
  }

  Widget _detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value))
      ]));
  void _sortSheet(FileManagerState state, FilesController controller) {
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final value in FileSort.values)
                RadioListTile(
                    value: value,
                    groupValue: state.sort,
                    title: Text(_sortLabel(value)),
                    onChanged: (v) {
                      controller.setSort(v!);
                      Navigator.pop(context);
                    }),
              ListTile(
                  leading: Icon(state.direction == SortDirection.ascending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward),
                  title: Text(state.direction == SortDirection.ascending
                      ? 'Croissant'
                      : 'Décroissant'),
                  onTap: () {
                    controller.toggleDirection();
                    Navigator.pop(context);
                  })
            ])));
  }

  String _sortLabel(FileSort value) => switch (value) {
        FileSort.name => 'Nom',
        FileSort.date => 'Date',
        FileSort.size => 'Taille',
        FileSort.type => 'Type'
      };
  Future<void> _confirmRemoveRoot(
      RootLocation root, FilesController controller) async {
    final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Retirer cet emplacement ?'),
                    content: Text(
                        '${root.name}\n\nLe dossier et ses fichiers ne seront pas supprimés de votre appareil.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Retirer de NexaFiles'))
                    ])) ??
        false;
    if (yes) await controller.removeRoot(root);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _error(Object error) => _message(
      error.toString().replaceFirst(RegExp(r'^\w+(Failure|Exception): '), ''));
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
          separatorBuilder: (_, __) =>
              const Icon(Icons.chevron_right, size: 18),
          itemBuilder: (_, i) => TextButton(
              onPressed: () => onTap(i),
              child: Text(path[i].entry.displayName, maxLines: 1))));
}

class _FileTile extends StatelessWidget {
  const _FileTile(
      {required this.entry,
      required this.item,
      required this.selected,
      required this.onTap,
      required this.onLongPress,
      required this.onMenu});
  final StorageEntry entry;
  final LibraryRecord? item;
  final bool selected;
  final VoidCallback onTap, onLongPress;
  final ValueChanged<String> onMenu;
  @override
  Widget build(BuildContext context) {
    final detail = entry.kind == StorageEntryKind.directory
        ? 'Dossier'
        : '${_typeLabel(entry)} • ${formatBytes(entry.size)}${entry.modifiedAt != null ? ' • ${_date(entry.modifiedAt!)}' : ''}';
    return ListTile(
        minVerticalPadding: 10,
        selected: selected,
        leading: SizedBox(
            width: 52,
            height: 58,
            child: _EntryVisual(entry: entry, item: item, size: 52)),
        title: Text(item?.title ?? entry.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item?.fraction != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: item!.fraction!.clamp(0, 1)),
            Text('${(item!.fraction! * 100).round()} % lu',
                style: Theme.of(context).textTheme.bodySmall)
          ]
        ]),
        isThreeLine: item?.fraction != null,
        onTap: onTap,
        onLongPress: onLongPress,
        trailing: PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: onMenu,
            itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                  if (entry.kind == StorageEntryKind.file)
                    const PopupMenuItem(
                        value: 'open', child: Text('Ouvrir avec…')),
                  const PopupMenuItem(
                      value: 'info', child: Text('Informations')),
                  const PopupMenuItem(value: 'delete', child: Text('Supprimer'))
                ]));
  }
}

class _FileGrid extends StatelessWidget {
  const _FileGrid(
      {required this.entry,
      required this.item,
      required this.selected,
      required this.onTap,
      required this.onLongPress});
  final StorageEntry entry;
  final LibraryRecord? item;
  final bool selected;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) => Card(
        color:
            selected ? Theme.of(context).colorScheme.secondaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: SizedBox(
                      width: double.infinity,
                      child: _EntryVisual(entry: entry, item: item, size: 64))),
              if (item?.fraction != null)
                LinearProgressIndicator(value: item!.fraction!.clamp(0, 1)),
              Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item?.title ?? entry.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            entry.kind == StorageEntryKind.directory
                                ? 'Dossier'
                                : '${entry.displayName.split('.').last.toUpperCase()} • ${formatBytes(entry.size)}',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.bodySmall),
                      ])),
            ])),
      );
}

class _EntryVisual extends StatelessWidget {
  const _EntryVisual(
      {required this.entry, required this.item, required this.size});
  final StorageEntry entry;
  final LibraryRecord? item;
  final double size;
  @override
  Widget build(BuildContext context) {
    final cover = item?.coverKey == null ? null : File(item!.coverKey!);
    if (cover != null && cover.existsSync()) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(cover, fit: BoxFit.cover, cacheWidth: 300));
    }
    final mime = entry.mimeType ?? '',
        previewable = mime.startsWith('image/') ||
            mime.startsWith('audio/') ||
            mime.startsWith('video/') ||
            RegExp(r'\.(jpe?g|png|webp|mp3|m4a|aac|ogg|wav|flac|mp4|m4v|webm|mkv|3gp)$',
                    caseSensitive: false)
                .hasMatch(entry.displayName);
    if (previewable) {
      return FutureBuilder<Uint8List?>(
          future: FilePreviewService.instance.imageThumbnail(entry),
          builder: (context, snapshot) => snapshot.data == null
              ? _placeholder(context)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.memory(snapshot.data!,
                      fit: BoxFit.cover, gaplessPlayback: true)));
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final category = _fileCategory(entry);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: category.softBackground(Theme.of(context).brightness),
            borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Center(
            child:
                Icon(category.icon, size: size * .62, color: category.color)));
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard(
      {required this.root, required this.onTap, required this.onMenu});
  final RootLocation root;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;
  @override
  Widget build(BuildContext context) {
    final used = root.totalBytes != null && root.freeBytes != null
            ? formatBytes(root.totalBytes! - root.freeBytes!)
            : null,
        total = root.totalBytes == null ? null : formatBytes(root.totalBytes);
    return Card(
        child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Stack(children: [
                  Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(
                                root.available
                                    ? Icons.storage_rounded
                                    : root.discovered
                                        ? Icons.phone_android
                                        : Icons.folder_off_outlined,
                                size: 28)),
                        const SizedBox(height: 10),
                        Text(root.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                            root.available
                                ? (used == null
                                    ? 'Disponible'
                                    : '$used / $total')
                                : root.discovered
                                    ? 'Autoriser l’accès'
                                    : 'Accès perdu',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall)
                      ])),
                  if (!root.discovered)
                    Positioned(
                        right: -8,
                        top: -8,
                        child: PopupMenuButton<String>(
                            onSelected: onMenu,
                            itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'favorite',
                                      child: Text(root.favorite
                                          ? 'Retirer des favoris'
                                          : 'Ajouter aux favoris')),
                                  if (!root.available)
                                    const PopupMenuItem(
                                        value: 'reauthorize',
                                        child: Text('Réautoriser')),
                                  const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Retirer de NexaFiles'))
                                ]))
                ]))));
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)));
}

class _OperationDialog extends StatefulWidget {
  const _OperationDialog(
      {required this.stream, required this.onCancel, required this.onDone});
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
    subscription = widget.stream.listen((p) {
      if (p.done) {
        widget.onDone();
      } else if (mounted) {
        setState(() => progress = p);
      }
    }, onError: (e) {
      if (mounted) setState(() => error = e);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(progress?.kind == FileOperationKind.move
              ? 'Déplacement'
              : 'Copie'),
          content: error != null
              ? Text('$error')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      LinearProgressIndicator(value: progress?.fraction),
                      const SizedBox(height: 12),
                      Text(progress?.currentName ?? 'Préparation…')
                    ]),
          actions: [
            TextButton(
                onPressed: () {
                  widget.onCancel();
                  Navigator.pop(context);
                },
                child: const Text('Annuler'))
          ]);
}

FileCategory _fileCategory(StorageEntry entry) {
  if (entry.kind == StorageEntryKind.directory) return FileCategory.folder;
  final dot = entry.displayName.lastIndexOf('.');
  return FileCategory.fromExtension(
      dot < 0 ? null : entry.displayName.substring(dot + 1));
}

String _date(DateTime value) {
  final d = value.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _typeLabel(StorageEntry entry) {
  final n = entry.displayName.toLowerCase();
  if (n.endsWith('.pdf')) return 'PDF';
  if (n.endsWith('.epub')) return 'EPUB';
  if (RegExp(r'\.(cbz|cbr|cb7)$').hasMatch(n)) return 'Comic';
  if (n.endsWith('.apk')) return 'Application Android';
  if (n.endsWith('.docx')) return 'Word';
  if (n.endsWith('.xlsx')) return 'Excel';
  if (n.endsWith('.pptx')) return 'PowerPoint';
  if (RegExp(r'\.(zip|rar|7z)$').hasMatch(n)) return 'Archive';
  if ((entry.mimeType ?? '').startsWith('image/')) return 'Image';
  return n.contains('.') ? n.split('.').last.toUpperCase() : 'Fichier';
}

String? _externalMime(DetectedFormat format, String? fallback) =>
    switch (format.content) {
      ContentKind.apk => 'application/vnd.android.package-archive',
      ContentKind.officeWord =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ContentKind.officeSpreadsheet =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ContentKind.officePresentation =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      _ => fallback
    };
