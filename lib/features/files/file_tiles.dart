import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/cache/file_preview_service.dart';
import '../../core/database/app_database.dart';
import '../../core/storage/storage_entry.dart';
import '../../shared/formatters.dart';
import 'file_actions.dart';

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
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        minVerticalPadding: 10,
        selected: selected,
        leading: SizedBox(
          width: 50,
          height: 56,
          child: Stack(
            fit: StackFit.expand,
            children: [
              EntryVisual(entry: entry, item: item, size: 50),
              if (selected) _SelectedMark(accent: accent),
            ],
          ),
        ),
        title: Text(
          item?.title ?? entry.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item?.fraction != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: item!.fraction!.clamp(0, 1),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(item!.fraction! * 100).round()} % lu',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: onMenu,
                itemBuilder: (_) =>
                    fileMenuItems(entry, favorite: favorite, canFavorite: true),
              ),
      ),
    );
  }
}

/// Accent check drawn over a selected thumbnail.
class _SelectedMark extends StatelessWidget {
  const _SelectedMark({required this.accent});
  final Color accent;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .85),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Icon(Icons.check_rounded, color: AppTheme.onColor(accent), size: 28),
  );
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: selected
            ? BorderSide(color: accent, width: 2.5)
            : BorderSide(color: context.surfaces.line),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EntryVisual(entry: entry, item: item, size: 64),
                    if (selected) _SelectedMark(accent: accent),
                  ],
                ),
              ),
            ),
            if (item?.fraction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item!.fraction!.clamp(0, 1),
                    minHeight: 4,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item?.title ?? entry.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    entry.kind == StorageEntryKind.directory
                        ? 'Dossier'
                        : '${entry.displayName.split('.').last.toUpperCase()} • ${formatBytes(entry.size)}',
                    maxLines: 1,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
