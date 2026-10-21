import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/platform/providers.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../reader/file_opener.dart';

final recentOpenEpochProvider = StateProvider<int>((ref) => 0);

/// Most recent unfinished reading, for the Files home card.
final continueReadingProvider =
    FutureProvider.autoDispose<List<ContinueReadingRecord>>((ref) {
      ref.watch(recentOpenEpochProvider);
      return ref.read(databaseProvider).continueReading();
    });
final recentsProvider = FutureProvider.autoDispose<List<RecentRecord>>((ref) {
  ref.watch(recentOpenEpochProvider);
  return ref.read(databaseProvider).recents();
});

class RecentsScreen extends ConsumerWidget {
  const RecentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(recentsProvider);
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Impossible de charger les récents',
        message: '$e',
        action: FilledButton(
          onPressed: () => ref.invalidate(recentsProvider),
          child: const Text('Réessayer'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'Aucun fichier ouvert récemment',
            message: 'Les fichiers ouverts depuis NexaFiles apparaîtront ici.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(recentsProvider),
          child: ListView.builder(
            padding: EdgeInsets.only(bottom: dockInset(context)),
            itemCount: items.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    '${items.length} fichier${items.length > 1 ? 's' : ''} ouvert${items.length > 1 ? 's' : ''} récemment',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final item = items[i - 1];
              final cover = item.coverKey == null ? null : File(item.coverKey!);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListTile(
                  minVerticalPadding: 10,
                  leading: SizedBox(
                    width: 48,
                    height: 62,
                    child: cover != null && cover.existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              cover,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                            ),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _formatIcon(item.format),
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatLabel(item.format)}${item.fraction == null ? '' : ' • ${(item.fraction! * 100).round()} % lu'}\n${_relative(item.openedAt)}',
                    maxLines: 2,
                  ),
                  isThreeLine: true,
                  onTap: () => openItem(context, ref, item),
                  trailing: item.fraction == null
                      ? null
                      : SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            value: item.fraction!.clamp(0, 1),
                            strokeWidth: 4,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Future<void> openItem(
    BuildContext context,
    WidgetRef ref,
    RecentRecord item,
  ) async {
    try {
      final entry = await ref
          .read(storageRepositoryProvider)
          .get(Uri.parse(item.uri));
      if (entry == null) throw StateError('absent');
      if (!context.mounted) return;
      await openFile(context, ref, entry, formatHint: item.format);
      ref.invalidate(recentsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ce fichier n’est plus disponible ou son format a changé.',
            ),
          ),
        );
      }
    }
  }
}

IconData _formatIcon(String format) => switch (format) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'epub' => Icons.menu_book_outlined,
  'comic' => Icons.auto_stories_outlined,
  'image' => Icons.image_outlined,
  'audio' => Icons.audio_file_outlined,
  'video' => Icons.video_file_outlined,
  'text' || 'markdown' => Icons.text_snippet_outlined,
  _ => Icons.insert_drive_file_outlined,
};
String _formatLabel(String format) => switch (format) {
  'pdf' => 'PDF',
  'epub' => 'EPUB',
  'comic' => 'Comic',
  'image' => 'Image',
  'audio' => 'Audio',
  'video' => 'Vidéo',
  'text' => 'Texte',
  'markdown' => 'Markdown',
  _ => 'Document',
};
String _relative(DateTime value) {
  final now = DateTime.now(),
      date = value.toLocal(),
      difference = now.difference(date);
  if (difference.inMinutes < 1) return 'À l’instant';
  if (difference.inMinutes < 60) return 'Il y a ${difference.inMinutes} min';
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Aujourd’hui, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Hier';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
