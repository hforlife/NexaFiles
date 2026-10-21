import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/cache/cache_manager.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/comics/comic_reader_adapter.dart';
import '../../core/database/database_provider.dart';
import '../../core/formats/detected_format.dart';
import '../../core/formats/format_detector.dart';
import '../../core/platform/providers.dart';
import '../../core/readers/document_adapters.dart';
import '../../core/readers/media_adapters.dart';
import '../../core/storage/storage_entry.dart';
import '../archives/archive_browser_screen.dart';
import '../files/files_controller.dart';
import '../player/audio_player_controller.dart';
import '../player/audio_player_screen.dart';
import '../recents/recents_screen.dart' show recentOpenEpochProvider;
import 'comic_cover_service.dart';
import 'comic_reader_screen.dart';
import 'document_cover_service.dart';
import 'document_reader_screens.dart';
import 'docx_reader_screen.dart';
import 'media_reader_screens.dart';

/// The single way to open a file, shared by Files, categories, Recents and
/// the Library: detects the real format, then shows the matching reader, the
/// archive browser, or hands the file to another app.
///
/// [siblings] are the other entries of the list the file was opened from;
/// they become the image gallery or the audio queue. [formatHint] is a
/// previously detected format, used when the bytes alone are ambiguous.
/// Throws when the file cannot be read; callers report the error.
Future<void> openFile(
  BuildContext context,
  WidgetRef ref,
  StorageEntry entry, {
  List<StorageEntry> siblings = const [],
  String? title,
  String? formatHint,
}) async {
  final storage = ref.read(storageRepositoryProvider);
  final source = storage.sourceFor(entry);
  final prefix = await storage.readPrefix(entry.uri);
  var detected = FormatDetector().detect(
    prefix: prefix,
    mimeType: entry.mimeType,
    fileName: entry.displayName,
  );

  // A plain ZIP/RAR may really be a comic: look inside before deciding.
  if (detected.container != ContainerFormat.none &&
      detected.content == ContentKind.archive) {
    final archive = await ref
        .read(archiveRegistryProvider)
        .open(source, detected);
    final names = (await archive.listEntries()).map((e) => e.path);
    detected = FormatDetector().detect(
      prefix: prefix,
      mimeType: entry.mimeType,
      fileName: entry.displayName,
      archiveEntries: names,
    );
    if (detected.content == ContentKind.archive) {
      if (!context.mounted) return archive.close();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArchiveBrowserScreen(
            name: entry.displayName,
            session: archive,
            storage: storage,
            roots: ref.read(filesControllerProvider).roots,
            defaultDestination: Uri.file(p.dirname(entry.uri.toFilePath())),
          ),
        ),
      );
      return;
    }
    await archive.close();
  }

  final hint = ContentKind.values.asNameMap()[formatHint];
  if (detected.content == ContentKind.unknown && hint != null) {
    detected = DetectedFormat(
      container: _containerFor(entry.displayName),
      content: hint,
      confidence: .8,
      evidence: const ['hint:recorded'],
    );
  }

  final adapter = ref.read(readerRegistryProvider).find(detected);
  if (adapter == null || _externalKinds.contains(detected.content)) {
    await storage.openExternal(
      entry.uri,
      mimeType: _externalMime(detected) ?? entry.mimeType,
    );
    return;
  }

  final session = await adapter.open(source, detected);
  final db = ref.read(databaseProvider), id = '${entry.uri}';
  final name = title ?? entry.displayName;
  await db.recordRecent(
    id: id,
    uri: id,
    name: entry.displayName,
    format: detected.content.name,
    mime: entry.mimeType,
    size: entry.size,
  );
  ref.read(recentOpenEpochProvider.notifier).state++;
  if (!context.mounted) {
    await session.dispose();
    return;
  }

  final covers = DocumentCoverService(CacheManager(), db);
  List<StorageEntry> siblingsWhere(bool Function(StorageEntry) test) {
    final list = [
      for (final e in siblings)
        if (e.kind == StorageEntryKind.file && test(e)) e,
    ]..sort((a, b) => naturalCompare(a.displayName, b.displayName));
    return list.any((e) => e.uri == entry.uri) ? list : [entry];
  }

  final Widget screen;
  switch (session) {
    case DocxReaderSession s:
      screen = DocxReaderScreen(session: s, storage: storage);
    case ComicReaderSession s:
      unawaited(ComicCoverService(CacheManager(), db).ensureCover(id, s.pages));
      screen = ComicReaderScreen(
        session: s,
        database: db,
        itemId: id,
        title: name,
      );
    case PdfReaderSession s:
      unawaited(covers.ensurePdf(id, s));
      screen = PdfReaderScreen(
        session: s,
        database: db,
        itemId: id,
        title: name,
      );
    case EpubReaderSession s:
      unawaited(covers.ensureEpub(id, s));
      screen = EpubReaderScreen(session: s, database: db, itemId: id);
    case TextReaderSession s:
      screen = TextReaderScreen(
        session: s,
        database: db,
        itemId: id,
        title: name,
        file: entry.uri.scheme == 'file' ? File(entry.uri.toFilePath()) : null,
      );
    case ImageReaderSession s:
      final images = siblingsWhere(
        (e) => (e.mimeType ?? '').startsWith('image/'),
      );
      screen = ImageReaderScreen(
        session: s,
        title: name,
        images: images,
        storage: storage,
        initialIndex: images.indexWhere((e) => e.uri == entry.uri),
      );
    case MediaReaderSession s when s.kind == ContentKind.audio:
      // Audio goes to the app-wide player: it keeps playing when the
      // screen is minimised to the mini player.
      await s.dispose();
      final songs = siblingsWhere(
        (e) => (e.mimeType ?? '').startsWith('audio/'),
      );
      unawaited(
        ref.read(audioPlayerProvider).play([
          for (final e in songs) MediaTrack('${e.uri}', e.displayName),
        ], songs.indexWhere((e) => e.uri == entry.uri).clamp(0, songs.length)),
      );
      if (context.mounted) await openAudioPlayer(context);
      return;
    case MediaReaderSession s:
      unawaited(ref.read(audioPlayerProvider).pause());
      screen = VideoReaderScreen(
        session: s,
        title: name,
        onOpenExternal: () => storage.openExternal(
          entry.uri,
          mimeType: entry.mimeType ?? 'video/*',
        ),
      );
    default:
      await session.dispose();
      throw StateError('Lecteur indisponible');
  }
  if (!context.mounted) {
    await session.dispose();
    return;
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

/// Formats NexaFiles does not render itself (Word is read in-app).
const _externalKinds = {
  ContentKind.officeSpreadsheet,
  ContentKind.officePresentation,
  ContentKind.apk,
};

String? _externalMime(DetectedFormat format) => switch (format.content) {
  ContentKind.apk => 'application/vnd.android.package-archive',
  ContentKind.officeSpreadsheet =>
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ContentKind.officePresentation =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  _ => null,
};

ContainerFormat _containerFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.cbz') || n.endsWith('.epub') || n.endsWith('.docx')) {
    return ContainerFormat.zip;
  }
  if (n.endsWith('.cbr')) return ContainerFormat.rar;
  if (n.endsWith('.cb7')) return ContainerFormat.sevenZip;
  return ContainerFormat.none;
}
