import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../reader/file_opener.dart';
import 'file_actions.dart';
import 'file_tiles.dart';

/// Presentation of a home-screen category (keys from [fileCategoryKeys]).
class CategoryInfo {
  const CategoryInfo(this.key, this.label, this.icon, this.color);
  final String key, label;
  final IconData icon;
  final Color color;
  bool get visual => key == 'images' || key == 'videos';
}

const categories = [
  CategoryInfo('images', 'Images', Icons.image_rounded, AppColors.image),
  CategoryInfo('videos', 'Vidéos', Icons.movie_rounded, AppColors.video),
  CategoryInfo('audio', 'Audio', Icons.music_note_rounded, AppColors.audio),
  CategoryInfo(
    'documents',
    'Documents',
    Icons.description_rounded,
    AppColors.document,
  ),
  CategoryInfo(
    'books',
    'Livres & BD',
    Icons.menu_book_rounded,
    AppColors.reading,
  ),
  CategoryInfo(
    'archives',
    'Archives',
    Icons.folder_zip_rounded,
    AppColors.archive,
  ),
  CategoryInfo('apps', 'Applications', Icons.android_rounded, AppColors.apk),
];

/// Totals for the home screen; refreshed with the volumes.
final categoryStatsProvider = FutureProvider<Map<String, CategoryStats>>(
  (ref) => ref.read(storageRepositoryProvider).categoryStats(),
);

enum _CategorySort { recent, name, size }

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.category});
  final CategoryInfo category;
  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  late Future<List<StorageEntry>> files = _load();
  String query = '';
  bool searching = false;
  _CategorySort sort = _CategorySort.recent;
  late bool grid = widget.category.visual;

  late final actions = FileActions(
    context,
    ref,
    onChanged: () async {
      // Background operations may finish after this screen is closed.
      if (!mounted) return;
      setState(() => files = _load());
      await files;
    },
  );

  Future<void> _longPress(StorageEntry entry) async {
    HapticFeedback.selectionClick();
    final action = await showFileActionsSheet(context, entry);
    if (action != null) await actions.handle(action, entry);
  }

  Future<List<StorageEntry>> _load() =>
      ref.read(storageRepositoryProvider).categoryFiles(widget.category.key);

  List<StorageEntry> _visible(List<StorageEntry> all) {
    final q = query.trim().toLowerCase();
    final list = [
      for (final e in all)
        if (q.isEmpty || e.displayName.toLowerCase().contains(q)) e,
    ];
    switch (sort) {
      case _CategorySort.recent:
        break; // already most recent first
      case _CategorySort.name:
        list.sort((a, b) => naturalCompare(a.displayName, b.displayName));
      case _CategorySort.size:
        list.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
    }
    return list;
  }

  Future<void> _open(StorageEntry entry, List<StorageEntry> siblings) async {
    try {
      await openFile(context, ref, entry, siblings: siblings);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce fichier.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Rechercher dans ${category.label.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => query = v),
              )
            : Text(category.label),
        actions: [
          IconButton(
            tooltip: searching ? 'Fermer la recherche' : 'Rechercher',
            onPressed: () => setState(() {
              searching = !searching;
              query = '';
            }),
            icon: Icon(searching ? Icons.close_rounded : Icons.search_rounded),
          ),
          IconButton(
            tooltip: grid ? 'Afficher en liste' : 'Afficher en grille',
            onPressed: () => setState(() => grid = !grid),
            icon: Icon(
              grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
            ),
          ),
          PopupMenuButton<_CategorySort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: sort,
            onSelected: (v) => setState(() => sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _CategorySort.recent,
                child: Text('Plus récents'),
              ),
              PopupMenuItem(value: _CategorySort.name, child: Text('Nom')),
              PopupMenuItem(
                value: _CategorySort.size,
                child: Text('Plus volumineux'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<StorageEntry>>(
        future: files,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Catégorie indisponible',
              message: 'L’index des fichiers n’a pas pu être lu.',
              action: FilledButton(
                onPressed: () => setState(() => files = _load()),
                child: const Text('Réessayer'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shown = _visible(snapshot.data!);
          if (shown.isEmpty) {
            return EmptyState(
              icon: query.isEmpty ? category.icon : Icons.search_off,
              title: query.isEmpty ? 'Aucun fichier' : 'Aucun résultat',
              message: query.isEmpty
                  ? 'Rien dans cette catégorie pour l’instant.'
                  : 'Essayez un autre nom.',
            );
          }
          final total = shown.fold<int>(0, (sum, e) => sum + (e.size ?? 0));
          final theme = Theme.of(context);
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconBubble(
                      icon: category.icon,
                      color: category.color,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shown.length} fichier${shown.length > 1 ? 's' : ''}',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            '${formatBytes(total)} · ${_sortLabel(sort)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => files = _load());
              await files;
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                if (grid && category.visual)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _VisualTile(
                        entry: shown[i],
                        video: category.key == 'videos',
                        onTap: () => _open(shown[i], shown),
                        onLongPress: () => _longPress(shown[i]),
                      ),
                    ),
                  )
                else if (grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: .78,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => FileGridTile(
                        entry: shown[i],
                        item: null,
                        selected: false,
                        onTap: () => _open(shown[i], shown),
                        onLongPress: () => _longPress(shown[i]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 32),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) => FileTile(
                        entry: shown[i],
                        item: null,
                        onTap: () => _open(shown[i], shown),
                        onLongPress: () => _longPress(shown[i]),
                        onMenu: (action) => actions.handle(action, shown[i]),
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
}

String _sortLabel(_CategorySort value) => switch (value) {
  _CategorySort.recent => 'plus récents d’abord',
  _CategorySort.name => 'par nom',
  _CategorySort.size => 'plus volumineux d’abord',
};

/// Square thumbnail; videos get a play badge.
class _VisualTile extends StatelessWidget {
  const _VisualTile({
    required this.entry,
    required this.video,
    required this.onTap,
    required this.onLongPress,
  });
  final StorageEntry entry;
  final bool video;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: entry.displayName,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            EntryVisual(entry: entry, item: null, size: 48),
            if (video)
              const Positioned(
                left: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
