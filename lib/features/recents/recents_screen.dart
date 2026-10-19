import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../core/platform/providers.dart';
import '../../shared/widgets/empty_state.dart';
import '../../core/formats/format_detector.dart';
import '../../core/formats/detected_format.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/readers/document_adapters.dart';
import '../reader/comic_reader_screen.dart';
import '../reader/document_reader_screens.dart';
import '../../core/readers/media_adapters.dart';
import '../reader/media_reader_screens.dart';

final recentOpenEpochProvider = StateProvider<int>((ref) => 0);
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
              child: const Text('Réessayer'))),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
              icon: Icons.history,
              title: 'Aucun fichier ouvert récemment',
              message:
                  'Les fichiers ouverts depuis NexaFiles apparaîtront ici.');
        }
        return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recentsProvider),
            child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text('Fichiers ouverts récemment',
                            style: Theme.of(context).textTheme.titleLarge));
                  }
                  final item = items[i - 1];
                  final cover =
                      item.coverKey == null ? null : File(item.coverKey!);
                  return ListTile(
                      minVerticalPadding: 10,
                      leading: SizedBox(
                          width: 48,
                          height: 62,
                          child: cover != null && cover.existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(cover,
                                      fit: BoxFit.cover, cacheWidth: 160))
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceVariant,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Icon(_formatIcon(item.format)))),
                      title: Text(item.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${_formatLabel(item.format)}${item.fraction == null ? '' : ' • ${(item.fraction! * 100).round()} % lu'}\n${_relative(item.openedAt)}',
                          maxLines: 2),
                      isThreeLine: true,
                      onTap: () => openItem(context, ref, item));
                }));
      },
    );
  }

  static Future<void> openItem(
      BuildContext context, WidgetRef ref, RecentRecord item) async {
    try {
      final storage = ref.read(storageRepositoryProvider),
          uri = Uri.parse(item.uri),
          entry = await storage.get(uri);
      if (entry == null) throw StateError('absent');
      final prefix = await storage.readPrefix(uri);
      var format = FormatDetector().detect(
          prefix: prefix,
          mimeType: entry.mimeType,
          fileName: entry.displayName);
      if ((format.content == ContentKind.unknown ||
              format.content == ContentKind.archive) &&
          ContentKind.values.any((e) => e.name == item.format)) {
        format = DetectedFormat(
            container: _container(entry.displayName),
            content: ContentKind.values.byName(item.format),
            confidence: .8,
            evidence: const ['recent:canonical']);
      }
      final session = await ref
              .read(readerRegistryProvider)
              .open(storage.sourceFor(entry), format),
          db = ref.read(databaseProvider);
      if (!context.mounted) {
        await session.dispose();
        return;
      }
      final Widget screen = switch (session) {
        ComicReaderSession s => ComicReaderScreen(
            session: s, database: db, itemId: item.id, title: item.name),
        PdfReaderSession s => PdfReaderScreen(
            session: s, database: db, itemId: item.id, title: item.name),
        EpubReaderSession s =>
          EpubReaderScreen(session: s, database: db, itemId: item.id),
        TextReaderSession s => TextReaderScreen(
            session: s, database: db, itemId: item.id, title: item.name),
        ImageReaderSession s => ImageReaderScreen(session: s, title: item.name),
        MediaReaderSession s when s.kind == ContentKind.audio =>
          AudioReaderScreen(session: s, title: item.name),
        MediaReaderSession s => VideoReaderScreen(session: s, title: item.name),
        _ => throw StateError('Lecteur indisponible')
      };
      await db.recordRecent(
          id: item.id,
          uri: item.uri,
          name: item.name,
          format: format.content.name,
          mime: item.mime,
          size: item.size);
      ref.invalidate(recentsProvider);
      if (context.mounted) {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => screen));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Ce fichier n’est plus disponible ou son format a changé.')));
      }
    }
  }
}

ContainerFormat _container(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.cbz') || n.endsWith('.epub')) return ContainerFormat.zip;
  if (n.endsWith('.cbr')) return ContainerFormat.rar;
  if (n.endsWith('.cb7')) return ContainerFormat.sevenZip;
  return ContainerFormat.none;
}

IconData _formatIcon(String format) => switch (format) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'epub' => Icons.menu_book_outlined,
      'comic' => Icons.auto_stories_outlined,
      'image' => Icons.image_outlined,
      'audio' => Icons.audio_file_outlined,
      'video' => Icons.video_file_outlined,
      'text' || 'markdown' => Icons.text_snippet_outlined,
      _ => Icons.insert_drive_file_outlined
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
      _ => 'Document'
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
      date.day == yesterday.day) return 'Hier';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
