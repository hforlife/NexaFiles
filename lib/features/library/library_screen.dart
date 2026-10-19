import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/formats/detected_format.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/library_scanner.dart';
import '../../core/platform/providers.dart';
import '../../core/readers/document_adapters.dart';
import '../reader/comic_reader_screen.dart';
import '../reader/document_reader_screens.dart';
import '../files/destination_picker.dart';
import '../files/files_controller.dart';

final libraryItemsProvider = FutureProvider.autoDispose<List<LibraryRecord>>(
    (ref) => LibraryRepository(ref.read(databaseProvider)).query());
final libraryRootsProvider =
    FutureProvider.autoDispose<List<LibraryRootRecord>>(
        (ref) => ref.read(databaseProvider).scanRoots());
final collectionsProvider = FutureProvider.autoDispose<List<CollectionRecord>>(
    (ref) => ref.read(databaseProvider).collections());

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String search = '';
  LibraryCategory category = LibraryCategory.all;
  LibraryFilter filter = LibraryFilter.all;
  LibrarySort sort = LibrarySort.dateAdded;
  @override
  Widget build(BuildContext context) {
    final all = ref.watch(libraryItemsProvider);
    return Column(children: [
      _toolbar(),
      Expanded(
          child: all.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Impossible de charger la bibliothèque.\n$e',
                      textAlign: TextAlign.center)),
              data: (raw) {
                final items = filterAndSortLibrary(raw,
                        search: search,
                        category: category,
                        filter: filter,
                        sort: sort),
                    continuing = raw
                        .where((e) =>
                            readingState(e) == ReadingState.inProgress &&
                            !e.unavailable)
                        .toList(),
                    recent = [...raw]
                      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
                return RefreshIndicator(
                    onRefresh: _refresh,
                    child: CustomScrollView(slivers: [
                      if (continuing.isNotEmpty)
                        SliverToBoxAdapter(
                            child: _horizontal(
                                'Continuer la lecture', continuing)),
                      if (recent.isNotEmpty &&
                          search.isEmpty &&
                          category == LibraryCategory.all &&
                          filter == LibraryFilter.all)
                        SliverToBoxAdapter(
                            child: _horizontal(
                                'Récemment ajoutés', recent.take(8).toList())),
                      SliverToBoxAdapter(
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                              child: Text('Tous les contenus (${items.length})',
                                  style:
                                      Theme.of(context).textTheme.titleLarge))),
                      if (items.isEmpty)
                        const SliverFillRemaining(
                            child: Center(
                                child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Aucun contenu. Ajoutez un dossier de bibliothèque pour commencer.',
                                        textAlign: TextAlign.center))))
                      else
                        SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                            sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 180,
                                        childAspectRatio: .62,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8),
                                delegate: SliverChildBuilderDelegate(
                                    (_, i) => _LibraryCard(
                                        item: items[i],
                                        onTap: () => _details(items[i]),
                                        onFavorite: () => _favorite(items[i])),
                                    childCount: items.length)))
                    ]));
              }))
    ]);
  }

  Widget _toolbar() => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(children: [
        TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Titre, fichier ou auteur',
                isDense: true),
            onChanged: (v) => setState(() => search = v)),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              DropdownButton<LibraryCategory>(
                  value: category,
                  onChanged: (v) => setState(() => category = v!),
                  items: LibraryCategory.values
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(_category(v))))
                      .toList()),
              const SizedBox(width: 12),
              DropdownButton<LibraryFilter>(
                  value: filter,
                  onChanged: (v) => setState(() => filter = v!),
                  items: LibraryFilter.values
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(_filter(v))))
                      .toList()),
              const SizedBox(width: 12),
              PopupMenuButton<LibrarySort>(
                  tooltip: 'Trier',
                  onSelected: (v) => setState(() => sort = v),
                  itemBuilder: (_) => LibrarySort.values
                      .map(
                          (v) => PopupMenuItem(value: v, child: Text(_sort(v))))
                      .toList(),
                  child: const Chip(
                      avatar: Icon(Icons.sort, size: 18),
                      label: Text('Trier'))),
              IconButton(
                  tooltip: 'Collections',
                  onPressed: _collections,
                  icon: const Icon(Icons.collections_bookmark_outlined)),
              IconButton(
                  tooltip: 'Dossiers de bibliothèque',
                  onPressed: _roots,
                  icon: const Icon(Icons.folder_special_outlined)),
              IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _scanAll,
                  icon: const Icon(Icons.refresh))
            ]))
      ]));
  Widget _horizontal(String title, List<LibraryRecord> items) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 8),
        SizedBox(
            height: 190,
            child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => SizedBox(
                    width: 125,
                    child: _LibraryCard(
                        item: items[i],
                        onTap: () => _open(items[i]),
                        onFavorite: () => _favorite(items[i])))))
      ]));
  Future<void> _refresh() async {
    ref.invalidate(libraryItemsProvider);
    await ref.read(libraryItemsProvider.future);
  }

  Future<void> _favorite(LibraryRecord item) async {
    await LibraryRepository(ref.read(databaseProvider))
        .favorite(item, !item.favorite);
    ref.invalidate(libraryItemsProvider);
  }

  Future<void> _roots() async {
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _RootsSheet(onScan: _scan));
  }

  Future<void> _scanAll() async {
    final roots = await ref.read(databaseProvider).scanRoots();
    if (roots.isEmpty) {
      await _roots();
      return;
    }
    for (final root in roots) {
      if (!mounted) return;
      await _scan(root);
    }
  }

  Future<void> _scan(LibraryRootRecord root) async {
    if (!mounted) return;
    await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ScanDialog(
            scanner: LibraryScanner(
                ref.read(storageRepositoryProvider), ref.read(databaseProvider),
                readers: ref.read(readerRegistryProvider)),
            root: root));
    ref.invalidate(libraryItemsProvider);
    ref.invalidate(libraryRootsProvider);
  }

  Future<void> _collections() async {
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _CollectionsSheet());
  }

  Future<void> _newCollection(BuildContext context, WidgetRef ref) async {
    final name = await _input(context, 'Nouvelle collection');
    if (name != null && name.trim().isNotEmpty) {
      await CollectionRepository(ref.read(databaseProvider)).create(name);
      ref.invalidate(collectionsProvider);
    }
  }

  Future<String?> _input(BuildContext context, String title,
      [String value = '']) async {
    final controller = TextEditingController(text: value);
    return showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(title),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, controller.text),
                      child: const Text('Valider'))
                ]));
  }

  Future<void> _details(LibraryRecord item) async {
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: _Cover(item: item, height: 190)),
                      const SizedBox(height: 12),
                      Text(item.title ?? item.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (item.author != null) Text(item.author!),
                      Text(
                          '${item.format.toUpperCase()} • ${item.size == null ? 'Taille inconnue' : '${item.size} octets'}'),
                      Text(
                          'Progression ${((item.fraction ?? 0) * 100).round()} %'),
                      if (item.unavailable)
                        const Text('Fichier introuvable',
                            style: TextStyle(color: Colors.red)),
                      Wrap(spacing: 8, children: [
                        FilledButton.icon(
                            onPressed: item.unavailable
                                ? null
                                : () {
                                    Navigator.pop(c);
                                    _open(item);
                                  },
                            icon: const Icon(Icons.play_arrow),
                            label: Text((item.fraction ?? 0) > 0
                                ? 'Reprendre'
                                : 'Lire')),
                        IconButton(
                            onPressed: () {
                              _favorite(item);
                              Navigator.pop(c);
                            },
                            icon: Icon(item.favorite
                                ? Icons.star
                                : Icons.star_border)),
                        IconButton(
                            onPressed: () => _addCollection(item),
                            icon: const Icon(Icons.playlist_add)),
                        IconButton(
                            onPressed: () => _bookmarks(item),
                            icon: const Icon(Icons.bookmarks_outlined)),
                        PopupMenuButton<ReadingState>(
                            onSelected: (v) async {
                              await LibraryRepository(
                                      ref.read(databaseProvider))
                                  .status(item, v);
                              ref.invalidate(libraryItemsProvider);
                              if (c.mounted) Navigator.pop(c);
                            },
                            itemBuilder: (_) => ReadingState.values
                                .map((v) => PopupMenuItem(
                                    value: v, child: Text(_state(v))))
                                .toList())
                      ]),
                      TextButton.icon(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                                    context: c,
                                    builder: (d) => AlertDialog(
                                            title: const Text(
                                                'Retirer de la bibliothèque ?'),
                                            content: const Text(
                                                'Le fichier physique ne sera pas supprimé. La progression et les signets associés seront supprimés.'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(d, false),
                                                  child: const Text('Annuler')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(d, true),
                                                  child: const Text('Retirer'))
                                            ])) ??
                                false;
                            if (ok) {
                              await LibraryRepository(
                                      ref.read(databaseProvider))
                                  .remove(item);
                              ref.invalidate(libraryItemsProvider);
                              if (c.mounted) Navigator.pop(c);
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Retirer de la bibliothèque'))
                    ]))));
  }

  Future<void> _addCollection(LibraryRecord item) async {
    final repo = CollectionRepository(ref.read(databaseProvider)),
        members = await repo.memberships(item.id);
    if (!mounted) return;
    await showModalBottomSheet(
        context: context,
        builder: (c) => Consumer(builder: (context, ref, _) {
              final values = ref.watch(collectionsProvider);
              return values.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('$e'),
                  data: (items) => ListView(shrinkWrap: true, children: [
                        ListTile(
                            leading: const Icon(Icons.add),
                            title: const Text('Nouvelle collection'),
                            onTap: () => _newCollection(context, ref)),
                        for (final col in items)
                          CheckboxListTile(
                              value: members.contains(col.id),
                              title: Text(col.name),
                              onChanged: (v) async {
                                v == true
                                    ? await repo.add(col.id, item.id)
                                    : await repo.remove(col.id, item.id);
                                if (c.mounted) Navigator.pop(c);
                              })
                      ]));
            }));
  }

  Future<void> _bookmarks(LibraryRecord item) async {
    final values =
        await BookmarkRepository(ref.read(databaseProvider)).list(item.id);
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        builder: (_) => ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Signets')),
              for (final b in values)
                ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(b.label ?? b.locator),
                    subtitle: Text(b.createdAt.toLocal().toString()),
                    onTap: () async {
                      await ref
                          .read(databaseProvider)
                          .saveProgress(item.id, b.locator, item.fraction ?? 0);
                      if (mounted) {
                        Navigator.pop(context);
                        _open(item);
                      }
                    }),
              if (values.isEmpty) const ListTile(title: Text('Aucun signet'))
            ]));
  }

  Future<void> _open(LibraryRecord item) async {
    try {
      final storage = ref.read(storageRepositoryProvider),
          entry = await storage.get(Uri.parse(item.uri));
      if (entry == null) throw StateError('absent');
      final kind = ContentKind.values.byName(item.format),
          name = entry.displayName.toLowerCase(),
          container = kind == ContentKind.epub || name.endsWith('.cbz')
              ? ContainerFormat.zip
              : name.endsWith('.cbr')
                  ? ContainerFormat.rar
                  : name.endsWith('.cb7')
                      ? ContainerFormat.sevenZip
                      : ContainerFormat.none,
          session = await ref.read(readerRegistryProvider).open(
              storage.sourceFor(entry),
              DetectedFormat(
                  container: container, content: kind, confidence: 1)),
          db = ref.read(databaseProvider);
      if (!mounted) {
        await session.dispose();
        return;
      }
      final Widget screen = switch (session) {
        ComicReaderSession s => ComicReaderScreen(
            session: s,
            database: db,
            itemId: item.id,
            title: item.title ?? item.name),
        PdfReaderSession s => PdfReaderScreen(
            session: s,
            database: db,
            itemId: item.id,
            title: item.title ?? item.name),
        EpubReaderSession s =>
          EpubReaderScreen(session: s, database: db, itemId: item.id),
        TextReaderSession s => TextReaderScreen(
            session: s,
            database: db,
            itemId: item.id,
            title: item.title ?? item.name),
        _ => throw StateError('lecteur')
      };
      await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      ref.invalidate(libraryItemsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fichier introuvable ou illisible.')));
      }
    }
  }

  String _category(LibraryCategory v) => const {
        LibraryCategory.all: 'Tous',
        LibraryCategory.books: 'Livres',
        LibraryCategory.comics: 'Mangas / BD',
        LibraryCategory.pdf: 'PDF',
        LibraryCategory.documents: 'Documents'
      }[v]!;
  String _filter(LibraryFilter v) => const {
        LibraryFilter.all: 'Tous',
        LibraryFilter.inProgress: 'En cours',
        LibraryFilter.finished: 'Terminés',
        LibraryFilter.unread: 'Non lus',
        LibraryFilter.favorites: 'Favoris'
      }[v]!;
  String _sort(LibrarySort v) => const {
        LibrarySort.titleAsc: 'Titre A–Z',
        LibrarySort.titleDesc: 'Titre Z–A',
        LibrarySort.dateAdded: 'Récemment ajouté',
        LibrarySort.lastRead: 'Récemment ouvert',
        LibrarySort.progress: 'Progression'
      }[v]!;
  String _state(ReadingState v) => const {
        ReadingState.notStarted: 'Non commencé',
        ReadingState.inProgress: 'En cours',
        ReadingState.finished: 'Terminé'
      }[v]!;
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard(
      {required this.item, required this.onTap, required this.onFavorite});
  final LibraryRecord item;
  final VoidCallback onTap, onFavorite;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Stack(fit: StackFit.expand, children: [
              _Cover(item: item),
              if (item.unavailable)
                Container(
                    color: Colors.black54,
                    child: const Center(
                        child: Icon(Icons.link_off,
                            color: Colors.white, size: 40))),
              Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                      onPressed: onFavorite,
                      icon: Icon(item.favorite ? Icons.star : Icons.star_border,
                          color: item.favorite ? Colors.amber : Colors.white)))
            ])),
            if ((item.fraction ?? 0) > 0)
              LinearProgressIndicator(value: item.fraction!.clamp(0, 1)),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title ?? item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(item.author ?? item.format.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall)
                    ]))
          ])));
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item, this.height});
  final LibraryRecord item;
  final double? height;
  @override
  Widget build(BuildContext context) {
    final file = item.coverKey == null ? null : File(item.coverKey!);
    if (file != null && file.existsSync()) {
      return Image.file(file,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          cacheWidth: 400);
    }
    final icon = switch (item.format) {
      'epub' => Icons.menu_book,
      'pdf' => Icons.picture_as_pdf,
      'comic' => Icons.auto_stories,
      _ => Icons.description
    };
    return Container(
        height: height,
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Center(
            child: Icon(icon,
                size: 54, color: Theme.of(context).colorScheme.primary)));
  }
}

class _ScanDialog extends StatefulWidget {
  const _ScanDialog({required this.scanner, required this.root});
  final LibraryScanner scanner;
  final LibraryRootRecord root;
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final cancel = LibraryScanCancellation();
  LibraryScanProgress? value;
  StreamSubscription? sub;
  @override
  void initState() {
    super.initState();
    sub = widget.scanner.scan(widget.root, cancellation: cancel).listen((v) {
      if (v.done) {
        Navigator.pop(context);
      } else if (mounted) {
        setState(() => value = v);
      }
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Analyse de la bibliothèque…'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(value?.current ?? 'Préparation…',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                    '${value?.scanned ?? 0} analysés • ${value?.failed ?? 0} ignorés')
              ]),
          actions: [
            TextButton(onPressed: cancel.cancel, child: const Text('Annuler'))
          ]);
}

class _RootsSheet extends ConsumerWidget {
  const _RootsSheet({required this.onScan});
  final ValueChanged<LibraryRootRecord> onScan;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roots = ref.watch(libraryRootsProvider);
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text('Dossiers de bibliothèque',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    onPressed: () async {
                      final storage = ref.read(storageRepositoryProvider);
                      final uri = await Navigator.push<Uri>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DestinationPicker(
                                  storage: storage,
                                  roots:
                                      ref.read(filesControllerProvider).roots,
                                  title: 'Dossier de bibliothèque')));
                      if (uri == null) return;
                      final entry = await storage.get(uri);
                      if (entry == null) return;
                      await ref
                          .read(databaseProvider)
                          .upsertScanRoot('${entry.uri}', entry.displayName);
                      ref.invalidate(libraryRootsProvider);
                      final root =
                          (await ref.read(databaseProvider).scanRoots())
                              .firstWhere((e) => e.uri == '${entry.uri}');
                      onScan(root);
                    },
                    icon: const Icon(Icons.add))
              ]),
              roots.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (values) => Flexible(
                          child: ListView(shrinkWrap: true, children: [
                        for (final root in values)
                          ListTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: Text(root.name),
                              subtitle: Text(root.lastScanAt == null
                                  ? 'Jamais analysé'
                                  : 'Dernière analyse : ${root.lastScanAt}'),
                              onTap: () => onScan(root),
                              trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () async {
                                    await ref
                                        .read(databaseProvider)
                                        .removeScanRoot(root.uri);
                                    ref.invalidate(libraryRootsProvider);
                                  })),
                        if (values.isEmpty)
                          const ListTile(title: Text('Aucun dossier surveillé'))
                      ])))
            ])));
  }
}

class _CollectionsSheet extends ConsumerWidget {
  const _CollectionsSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(collectionsProvider),
        repo = CollectionRepository(ref.read(databaseProvider));
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text('Collections',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    onPressed: () async {
                      final name = await _name(context, 'Nouvelle collection');
                      if (name != null && name.trim().isNotEmpty) {
                        await repo.create(name);
                        ref.invalidate(collectionsProvider);
                      }
                    },
                    icon: const Icon(Icons.add))
              ]),
              values.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (items) => Flexible(
                          child: ListView(shrinkWrap: true, children: [
                        for (final item in items)
                          ListTile(
                              leading: const Icon(Icons.collections_bookmark),
                              title: Text(item.name),
                              subtitle: Text('${item.itemCount} élément(s)'),
                              trailing: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'rename') {
                                      final name = await _name(
                                          context, 'Renommer', item.name);
                                      if (name != null &&
                                          name.trim().isNotEmpty) {
                                        await repo.rename(item.id, name);
                                      }
                                    }
                                    if (v == 'delete') {
                                      await repo.delete(item.id);
                                    }
                                    ref.invalidate(collectionsProvider);
                                  },
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Renommer')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Supprimer'))
                                      ])),
                        if (items.isEmpty)
                          const ListTile(title: Text('Aucune collection'))
                      ])))
            ])));
  }

  Future<String?> _name(BuildContext context, String title,
      [String value = '']) {
    final input = TextEditingController(text: value);
    return showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(title),
                content: TextField(controller: input, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, input.text),
                      child: const Text('Valider'))
                ]));
  }
}
