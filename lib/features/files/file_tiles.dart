import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/cache/file_preview_service.dart';
import '../../core/database/app_database.dart';
import '../../core/storage/storage_entry.dart';
import '../../shared/formatters.dart';

/// List row for a file or folder: thumbnail or cover, name, type, size, date
/// and reading progress when the file is in the library.
class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.entry,
    required this.item,
    required this.onTap,
    this.selected = false,
    this.favorite = false,
    this.onLongPress,
    this.onMenu,
  });
  final StorageEntry entry;
  final LibraryRecord? item;
  final bool selected, favorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Actions menu (rename, info…); hidden when null.
  final ValueChanged<String>? onMenu;
  @override
  Widget build(BuildContext context) {
    final detail = entry.kind == StorageEntryKind.directory
        ? 'Dossier'
        : '${fileTypeLabel(entry)} • ${formatBytes(entry.size)}${entry.modifiedAt != null ? ' • ${formatShortDate(entry.modifiedAt!)}' : ''}';
    return ListTile(
      minVerticalPadding: 10,
      selected: selected,
      leading: SizedBox(
        width: 52,
        height: 58,
        child: EntryVisual(entry: entry, item: item, size: 52),
      ),
      title: Text(
        item?.title ?? entry.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (item?.fraction != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: item!.fraction!.clamp(0, 1)),
            Text(
              '${(item!.fraction! * 100).round()} % lu',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      isThreeLine: item?.fraction != null,
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: onMenu == null
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: onMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                if (entry.kind == StorageEntryKind.directory)
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(
                      favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    ),
                  ),
                if (entry.kind == StorageEntryKind.file)
                  const PopupMenuItem(
                    value: 'open',
                    child: Text('Ouvrir avec…'),
                  ),
                const PopupMenuItem(value: 'info', child: Text('Informations')),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.entry,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final StorageEntry entry;
  final LibraryRecord? item;
  final bool selected;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) => Card(
    color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: EntryVisual(entry: entry, item: item, size: 64),
            ),
          ),
          if (item?.fraction != null)
            LinearProgressIndicator(value: item!.fraction!.clamp(0, 1)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.title ?? entry.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  entry.kind == StorageEntryKind.directory
                      ? 'Dossier'
                      : '${entry.displayName.split('.').last.toUpperCase()} • ${formatBytes(entry.size)}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EntryVisual extends StatelessWidget {
  const EntryVisual({
    super.key,
    required this.entry,
    required this.item,
    required this.size,
  });
  final StorageEntry entry;
  final LibraryRecord? item;
  final double size;
  @override
  Widget build(BuildContext context) {
    final coverKey = item?.coverKey;
    if (coverKey != null) {
      // No existsSync() during build: a missing cover falls back below.
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.file(
          File(coverKey),
          fit: BoxFit.cover,
          cacheWidth: 300,
          errorBuilder: (context, _, _) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final mime = entry.mimeType ?? '',
        previewable =
            mime.startsWith('image/') ||
            mime.startsWith('audio/') ||
            mime.startsWith('video/') ||
            RegExp(
              r'\.(jpe?g|png|webp|mp3|m4a|aac|ogg|wav|flac|mp4|m4v|webm|mkv|3gp)$',
              caseSensitive: false,
            ).hasMatch(entry.displayName);
    if (previewable) {
      return FutureBuilder<Uint8List?>(
        future: FilePreviewService.instance.imageThumbnail(entry),
        builder: (context, snapshot) => snapshot.data == null
            ? _placeholder(context)
            : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final category = fileCategoryOf(entry);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: category.softBackground(Theme.of(context).brightness),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Center(
        child: Icon(category.icon, size: size * .62, color: category.color),
      ),
    );
  }
}

FileCategory fileCategoryOf(StorageEntry entry) {
  if (entry.kind == StorageEntryKind.directory) return FileCategory.folder;
  final dot = entry.displayName.lastIndexOf('.');
  return FileCategory.fromExtension(
    dot < 0 ? null : entry.displayName.substring(dot + 1),
  );
}

String formatShortDate(DateTime value) {
  final d = value.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String fileTypeLabel(StorageEntry entry) {
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
