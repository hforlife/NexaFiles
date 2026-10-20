import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../reader/file_opener.dart';
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
                  border: InputBorder.none,
                  filled: false,
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
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
          PopupMenuButton<_CategorySort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
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
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${shown.length} fichier${shown.length > 1 ? 's' : ''} • ${formatBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall,
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
                if (category.visual)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 130,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: shown.length,
                      itemBuilder: (_, i) => InkWell(
                        onTap: () => _open(shown[i], shown),
                        child: EntryVisual(
                          entry: shown[i],
                          item: null,
                          size: 48,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => FileTile(
                      entry: shown[i],
                      item: null,
                      onTap: () => _open(shown[i], shown),
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
