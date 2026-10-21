import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/library/library_repository.dart';
import '../../core/library/library_scanner.dart';
import '../../core/platform/providers.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../reader/file_opener.dart';
import '../files/destination_picker.dart';
import '../files/files_controller.dart';

final libraryItemsProvider = FutureProvider.autoDispose<List<LibraryRecord>>(
  (ref) => LibraryRepository(ref.read(databaseProvider)).query(),
);
final libraryRootsProvider =
    FutureProvider.autoDispose<List<LibraryRootRecord>>(
      (ref) => ref.read(databaseProvider).scanRoots(),
    );
final collectionsProvider = FutureProvider.autoDispose<List<CollectionRecord>>(
  (ref) => ref.read(databaseProvider).collections(),
);

/// The library ("Salon de lecture"): warm paper surfaces and serif titles.
/// Its theme wraps the whole tab so sheets and dialogs opened from it share
/// the same look.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.library(Theme.of(context));
    return Theme(
      data: theme,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: const _LibraryView(),
      ),
    );
  }
}

class _LibraryView extends ConsumerStatefulWidget {
  const _LibraryView();
  @override
  ConsumerState<_LibraryView> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<_LibraryView> {
  String search = '';
  bool searching = false;
  LibraryCategory category = LibraryCategory.all;
  LibraryFilter filter = LibraryFilter.all;
  LibrarySort sort = LibrarySort.dateAdded;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(libraryItemsProvider);
    return SafeArea(
      bottom: false,
      child: all.when(
        loading: () => Column(
          children: [
            _header(const []),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
        error: (e, _) => Column(
          children: [
            _header(const []),
            Expanded(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Impossible de charger la bibliothèque',
                message: '$e',
              ),
            ),
          ],
        ),
        data: (raw) {
          final items = filterAndSortLibrary(
                raw,
                search: search,
                category: category,
                filter: filter,
                sort: sort,
              ),
              continuing = raw
                  .where(
                    (e) =>
                        readingState(e) == ReadingState.inProgress &&
                        !e.unavailable,
                  )
                  .toList(),
              recent = [...raw]..sort((a, b) => b.addedAt.compareTo(a.addedAt)),
              browsing =
                  search.isEmpty &&
                  category == LibraryCategory.all &&
                  filter == LibraryFilter.all;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(raw, continuing.length)),
                if (searching) SliverToBoxAdapter(child: _searchField()),
                if (raw.isNotEmpty)
                  SliverToBoxAdapter(child: _categoryBar(raw)),
                if (browsing && continuing.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      child: _ResumeHero(
                        item: continuing.first,
                        onTap: () => _open(continuing.first),
                      ),
                    ),
                  ),
                  if (continuing.length > 1)
                    SliverToBoxAdapter(
                      child: _shelf('En cours', continuing.skip(1).toList()),
                    ),
                ],
                if (browsing && recent.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _shelf(
                      'Récemment ajoutés',
                      recent.take(10).toList(),
                    ),
                  ),
                if (raw.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SectionTitle(
                      browsing ? 'Toute la collection' : 'Résultats',
                      trailing: _countPill(items.length),
                    ),
                  ),
                if (items.isEmpty)
                  // Natural height so it scrolls on small screens.
                  SliverToBoxAdapter(
                    child: raw.isEmpty
                        ? EmptyState(
                            icon: Icons.auto_stories_rounded,
                            title: 'Votre salon de lecture est vide',
                            message:
                                'Choisissez un dossier contenant vos livres, mangas et PDF : NexaFiles les retrouve et mémorise votre progression.',
                            action: FilledButton.icon(
                              onPressed: _roots,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                              ),
                              label: const Text('Choisir un dossier'),
                            ),
                          )
                        : const EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Aucun résultat',
                            message: 'Modifiez la recherche ou les filtres.',
                          ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, dockInset(context)),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 150,
                            childAspectRatio: .5,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 18,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _BookCard(
                          item: items[i],
                          onTap: () => _details(items[i]),
                        ),
                        childCount: items.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(List<LibraryRecord> raw, [int reading = 0]) {
    final filtered =
        filter != LibraryFilter.all || sort != LibrarySort.dateAdded;
    return PageHeader(
      eyebrow: 'Salon de lecture',
      title: const Text('Bibliothèque'),
      subtitle: raw.isEmpty
          ? null
          : '${raw.length} titre${raw.length > 1 ? 's' : ''}'
                '${reading > 0 ? ' · $reading en cours' : ''}',
      actions: [
        RoundIconButton(
          icon: searching ? Icons.close_rounded : Icons.search_rounded,
          tooltip: searching ? 'Fermer la recherche' : 'Rechercher',
          filled: searching,
          onPressed: () => setState(() {
            searching = !searching;
            if (!searching) search = '';
          }),
        ),
        RoundIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Filtrer et trier',
          badge: filtered,
          onPressed: _filterSheet,
        ),
        RoundIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'Plus',
          onPressed: _moreSheet,
        ),
      ],
    );
  }

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: TextField(
      autofocus: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Titre, fichier ou auteur',
      ),
      onChanged: (v) => setState(() => search = v),
    ),
  );

  Widget _categoryBar(List<LibraryRecord> raw) => SizedBox(
    height: 58,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      children: [
        for (final value in LibraryCategory.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ShelfChip(
              label: _category(value),
              count: value == LibraryCategory.all
                  ? raw.length
                  : filterAndSortLibrary(
                      raw,
                      search: '',
                      category: value,
                      filter: LibraryFilter.all,
                      sort: sort,
                    ).length,
              selected: category == value,
              onTap: () => setState(() => category = value),
            ),
          ),
      ],
    ),
  );

  Widget _countPill(int count) {
    final s = context.surfaces;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.cardAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count objet${count > 1 ? 's' : ''}',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: s.muted),
      ),
    );
  }

  Widget _shelf(String title, List<LibraryRecord> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle(title),
      SizedBox(
        height: 236,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, i) => SizedBox(
            width: 118,
            child: _BookCard(item: items[i], onTap: () => _open(items[i])),
          ),
        ),
      ),
    ],
  );

  Future<void> _moreSheet() => showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, label, hint, action) in [
              (
                Icons.collections_bookmark_outlined,
                'Collections',
                'Regroupez vos séries et lectures',
                _collections,
              ),
              (
                Icons.folder_special_outlined,
                'Dossiers de bibliothèque',
                'Choisissez où chercher vos livres',
                _roots,
              ),
              (
                Icons.sync_rounded,
                'Analyser maintenant',
                'Rechercher les nouveaux fichiers',
                _scanAll,
              ),
            ])
              ListTile(
                leading: IconBubble(
                  icon: icon,
                  color: Theme.of(c).colorScheme.primary,
                  size: 42,
                ),
                title: Text(label),
                subtitle: Text(hint),
                onTap: () {
                  Navigator.pop(c);
                  action();
                },
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _details(LibraryRecord item) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final theme = Theme.of(c), s = c.surfaces;
        final fraction = (item.fraction ?? 0).clamp(0.0, 1.0);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 168,
                      child: _Cover(item: item, elevated: true),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Tag(_formatLabel(item.format)),
                              if (item.size != null)
                                _Tag(formatBytes(item.size)),
                              _Tag(_state(readingState(item))),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.title ?? item.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (item.author != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.author!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: AppFonts.serif,
                                fontStyle: FontStyle.italic,
                                color: s.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Progression', style: theme.textTheme.labelLarge),
                    const Spacer(),
                    Text(
                      '${(fraction * 100).round()} %',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: fraction, minHeight: 8),
                ),
                if (item.unavailable) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.link_off_rounded,
                        color: theme.colorScheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Fichier introuvable',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: item.unavailable
                        ? null
                        : () {
                            Navigator.pop(c);
                            _open(item);
                          },
                    icon: const Icon(Icons.auto_stories_rounded),
                    label: Text(fraction > 0 ? 'Reprendre la lecture' : 'Lire'),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _SheetAction(
                      icon: item.favorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      label: item.favorite ? 'Favori' : 'Favoris',
                      active: item.favorite,
                      onTap: () {
                        _favorite(item);
                        Navigator.pop(c);
                      },
                    ),
                    _SheetAction(
                      icon: Icons.playlist_add_rounded,
                      label: 'Collection',
                      onTap: () => _addCollection(item),
                    ),
                    _SheetAction(
                      icon: Icons.bookmarks_outlined,
                      label: 'Signets',
                      onTap: () => _bookmarks(item),
                    ),
                    Expanded(
                      child: PopupMenuButton<ReadingState>(
                        tooltip: 'Statut de lecture',
                        onSelected: (v) async {
                          await LibraryRepository(
                            ref.read(databaseProvider),
                          ).status(item, v);
                          ref.invalidate(libraryItemsProvider);
                          if (c.mounted) Navigator.pop(c);
                        },
                        itemBuilder: (_) => ReadingState.values
                            .map(
                              (v) => PopupMenuItem(
                                value: v,
                                child: Text(_state(v)),
                              ),
                            )
                            .toList(),
                        child: const _SheetActionContent(
                          icon: Icons.flag_outlined,
                          label: 'Statut',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () async {
                      final ok =
                          await showDialog<bool>(
                            context: c,
                            builder: (d) => AlertDialog(
                              title: const Text('Retirer de la bibliothèque ?'),
                              content: const Text(
                                'Le fichier physique ne sera pas supprimé. La progression et les signets associés seront supprimés.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: const Text('Annuler'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(d, true),
                                  child: const Text('Retirer'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (ok) {
                        await LibraryRepository(
                          ref.read(databaseProvider),
                        ).remove(item);
                        ref.invalidate(libraryItemsProvider);
                        if (c.mounted) Navigator.pop(c);
                      }
                    },
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    label: const Text('Retirer de la bibliothèque'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatLabel(String format) => switch (format) {
    'epub' => 'EPUB',
    'pdf' => 'PDF',
    'comic' => 'Manga / BD',
    _ => format.toUpperCase(),
  };

  Future<void> _filterSheet() => showModalBottomSheet<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) {
        void update(VoidCallback change) {
          setSheet(change);
          setState(() {});
        }

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text('Afficher', style: Theme.of(c).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in LibraryFilter.values)
                    ChoiceChip(
                      label: Text(_filter(value)),
                      selected: filter == value,
                      onSelected: (_) => update(() => filter = value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Trier par', style: Theme.of(c).textTheme.titleSmall),
              RadioGroup<LibrarySort>(
                groupValue: sort,
                onChanged: (v) => update(() => sort = v!),
                child: Column(
                  children: [
                    for (final value in LibrarySort.values)
                      RadioListTile<LibrarySort>(
                        value: value,
                        title: Text(_sort(value)),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _refresh() async {
    ref.invalidate(libraryItemsProvider);
    await ref.read(libraryItemsProvider.future);
  }

  Future<void> _favorite(LibraryRecord item) async {
    await LibraryRepository(
      ref.read(databaseProvider),
    ).favorite(item, !item.favorite);
    ref.invalidate(libraryItemsProvider);
  }

  Future<void> _roots() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RootsSheet(onScan: _scan),
    );
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
          ref.read(storageRepositoryProvider),
          ref.read(databaseProvider),
          readers: ref.read(readerRegistryProvider),
        ),
        root: root,
      ),
    );
    ref.invalidate(libraryItemsProvider);
    ref.invalidate(libraryRootsProvider);
  }

  Future<void> _collections() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CollectionsSheet(),
    );
  }

  Future<void> _newCollection(BuildContext context, WidgetRef ref) async {
    final name = await _input(context, 'Nouvelle collection');
    if (name != null && name.trim().isNotEmpty) {
      await CollectionRepository(ref.read(databaseProvider)).create(name);
      ref.invalidate(collectionsProvider);
    }
  }

  Future<String?> _input(
    BuildContext context,
    String title, [
    String value = '',
  ]) async {
    final controller = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCollection(LibraryRecord item) async {
    final repo = CollectionRepository(ref.read(databaseProvider)),
        members = await repo.memberships(item.id);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (c) => Consumer(
        builder: (context, ref, _) {
          final values = ref.watch(collectionsProvider);
          return values.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (items) => ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Nouvelle collection'),
                  onTap: () => _newCollection(context, ref),
                ),
                for (final col in items)
                  CheckboxListTile(
                    value: members.contains(col.id),
                    title: Text(col.name),
                    onChanged: (v) async {
                      v == true
                          ? await repo.add(col.id, item.id)
                          : await repo.remove(col.id, item.id);
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _bookmarks(LibraryRecord item) async {
    final values = await BookmarkRepository(
      ref.read(databaseProvider),
    ).list(item.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
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
              },
            ),
          if (values.isEmpty) const ListTile(title: Text('Aucun signet')),
        ],
      ),
    );
  }

  Future<void> _open(LibraryRecord item) async {
    try {
      final entry = await ref
          .read(storageRepositoryProvider)
          .get(Uri.parse(item.uri));
      if (entry == null) throw StateError('absent');
      if (!mounted) return;
      await openFile(
        context,
        ref,
        entry,
        title: item.title ?? item.name,
        formatHint: item.format,
      );
      ref.invalidate(libraryItemsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fichier introuvable ou illisible.')),
        );
      }
    }
  }

  String _category(LibraryCategory v) => const {
    LibraryCategory.all: 'Tous',
    LibraryCategory.books: 'Livres',
    LibraryCategory.comics: 'Mangas / BD',
    LibraryCategory.pdf: 'PDF',
    LibraryCategory.documents: 'Documents',
  }[v]!;
  String _filter(LibraryFilter v) => const {
    LibraryFilter.all: 'Tous',
    LibraryFilter.inProgress: 'En cours',
    LibraryFilter.finished: 'Terminés',
    LibraryFilter.unread: 'Non lus',
    LibraryFilter.favorites: 'Favoris',
  }[v]!;
  String _sort(LibrarySort v) => const {
    LibrarySort.titleAsc: 'Titre A–Z',
    LibrarySort.titleDesc: 'Titre Z–A',
    LibrarySort.dateAdded: 'Récemment ajouté',
    LibrarySort.lastRead: 'Récemment ouvert',
    LibrarySort.progress: 'Progression',
  }[v]!;
  String _state(ReadingState v) => const {
    ReadingState.notStarted: 'Non commencé',
    ReadingState.inProgress: 'En cours',
    ReadingState.finished: 'Terminé',
  }[v]!;
}

/// Category pill with its count: ink when selected, paper otherwise.
class _ShelfChip extends StatelessWidget {
  const _ShelfChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final fg = selected ? s.canvas : s.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? s.ink : s.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? s.ink : s.line, width: 1.2),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    TextSpan(
                      text: '  $count',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: .55),
                      ),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontFamily: AppFonts.body,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large "pick up where you left off" card over a blurred cover.
class _ResumeHero extends StatelessWidget {
  const _ResumeHero({required this.item, required this.onTap});
  final LibraryRecord item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    final fraction = (item.fraction ?? 0).clamp(0.0, 1.0);
    final cover = item.coverKey;
    return Material(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF1B1611),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Image.file(
                    File(cover),
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: .4)],
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xE6120E0A), Color(0x99120E0A)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 106,
                      child: _Cover(item: item, elevated: true),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Reprendre',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFamily: AppFonts.serif,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.title ?? item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          if (item.author != null)
                            Text(
                              item.author!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white60,
                              ),
                            ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: fraction,
                                    minHeight: 5,
                                    color: accent,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${(fraction * 100).round()} %',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                  color: AppTheme.onColor(accent),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Continuer',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppTheme.onColor(accent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

/// Book on the shelf: cover with depth, reading line, title and author.
class _BookCard extends StatelessWidget {
  const _BookCard({required this.item, required this.onTap});
  final LibraryRecord item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = context.surfaces;
    final fraction = (item.fraction ?? 0).clamp(0.0, 1.0);
    final finished = readingState(item) == ReadingState.finished;
    return Semantics(
      button: true,
      label: item.title ?? item.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(item: item, elevated: true),
                  if (item.unavailable)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: const ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Icon(
                            Icons.link_off_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                  if (item.favorite || finished)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: s.card,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.favorite
                              ? Icons.star_rounded
                              : Icons.check_rounded,
                          size: 15,
                          color: item.favorite
                              ? AppColors.folder
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Reading line, like a bookmark ribbon under the cover.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: finished ? 1 : fraction,
                minHeight: 3,
                color: finished ? s.ink : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              item.title ?? item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(height: 1.2),
            ),
            Text(
              item.author ??
                  (fraction > 0
                      ? '${(fraction * 100).round()} % lu'
                      : item.format.toUpperCase()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item, this.elevated = false});
  final LibraryRecord item;
  final bool elevated;
  @override
  Widget build(BuildContext context) {
    final key = item.coverKey;
    final image = key == null
        ? _placeholder(context)
        : Image.file(
            File(key),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 400,
            errorBuilder: (context, _, _) => _placeholder(context),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            // Spine highlight for a printed-book feel.
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x33000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final s = context.surfaces, accent = Theme.of(context).colorScheme.primary;
    final icon = switch (item.format) {
      'epub' => Icons.menu_book_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'comic' => Icons.auto_stories_rounded,
      _ => Icons.description_rounded,
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            s.cardAlt,
            Color.alphaBlend(accent.withValues(alpha: .18), s.cardAlt),
          ],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 26, color: accent),
          const Spacer(),
          Text(
            item.title ?? item.name,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.serif,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.15,
              color: s.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.cardAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: s.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: _SheetActionContent(icon: icon, label: label, active: active),
    ),
  );
}

class _SheetActionContent extends StatelessWidget {
  const _SheetActionContent({
    required this.icon,
    required this.label,
    this.active = false,
  });
  final IconData icon;
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: s.cardAlt, shape: BoxShape.circle),
            child: Icon(icon, color: active ? AppColors.folder : s.ink),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
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
      if (!mounted) return;
      if (v.done) {
        Navigator.pop(context);
      } else {
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
        Text(
          value?.current ?? 'Préparation…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text('${value?.scanned ?? 0} analysés • ${value?.failed ?? 0} ignorés'),
      ],
    ),
    actions: [
      TextButton(onPressed: cancel.cancel, child: const Text('Annuler')),
    ],
  );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dossiers de bibliothèque',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final storage = ref.read(storageRepositoryProvider);
                    final uri = await Navigator.push<Uri>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DestinationPicker(
                          storage: storage,
                          roots: ref.read(filesControllerProvider).roots,
                          title: 'Dossier de bibliothèque',
                        ),
                      ),
                    );
                    if (uri == null) return;
                    final entry = await storage.get(uri);
                    if (entry == null) return;
                    await ref
                        .read(databaseProvider)
                        .upsertScanRoot('${entry.uri}', entry.displayName);
                    ref.invalidate(libraryRootsProvider);
                    final root = (await ref.read(databaseProvider).scanRoots())
                        .firstWhere((e) => e.uri == '${entry.uri}');
                    onScan(root);
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            roots.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (values) => Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final root in values)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(root.name),
                        subtitle: Text(
                          root.lastScanAt == null
                              ? 'Jamais analysé'
                              : 'Dernière analyse : ${root.lastScanAt}',
                        ),
                        onTap: () => onScan(root),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () async {
                            await ref
                                .read(databaseProvider)
                                .removeScanRoot(root.uri);
                            ref.invalidate(libraryRootsProvider);
                          },
                        ),
                      ),
                    if (values.isEmpty)
                      const ListTile(title: Text('Aucun dossier surveillé')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collections',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final name = await _name(context, 'Nouvelle collection');
                    if (name != null && name.trim().isNotEmpty) {
                      await repo.create(name);
                      ref.invalidate(collectionsProvider);
                    }
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            values.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (items) => Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      ListTile(
                        leading: const Icon(Icons.collections_bookmark),
                        title: Text(item.name),
                        subtitle: Text('${item.itemCount} élément(s)'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'rename') {
                              final name = await _name(
                                context,
                                'Renommer',
                                item.name,
                              );
                              if (name != null && name.trim().isNotEmpty) {
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
                              child: Text('Renommer'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
                          ],
                        ),
                      ),
                    if (items.isEmpty)
                      const ListTile(title: Text('Aucune collection')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _name(
    BuildContext context,
    String title, [
    String value = '',
  ]) {
    final input = TextEditingController(text: value);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}
