import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import '../cache/cache_manager.dart';
import '../comics/comic_reader_adapter.dart';
import '../database/app_database.dart';
import '../formats/detected_format.dart';
import '../readers/document_adapters.dart';
import '../readers/reader_core.dart';
import '../storage/storage_entry.dart';
import '../storage/storage_repository.dart';

class LibraryScanCancellation {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class LibraryScanProgress {
  const LibraryScanProgress(
      {required this.scanned,
      required this.added,
      required this.unchanged,
      required this.failed,
      this.current,
      this.done = false,
      this.cancelled = false});
  final int scanned, added, unchanged, failed;
  final String? current;
  final bool done, cancelled;
}

class LibraryScanner {
  LibraryScanner(this.storage, this.database, {this.readers});
  final StorageRepository storage;
  final AppDatabase database;
  final ReaderRegistry? readers;
  Future<void> _coverTail = Future.value();
  Stream<LibraryScanProgress> scan(LibraryRootRecord root,
      {LibraryScanCancellation? cancellation}) async* {
    final seen = <String>{};
    var scanned = 0, added = 0, unchanged = 0, failed = 0;
    final pending = <Uri>[Uri.parse(root.uri)];
    while (pending.isNotEmpty && cancellation?.cancelled != true) {
      final directory = pending.removeLast();
      List<StorageEntry> entries;
      try {
        entries = await storage.list(directory);
      } catch (_) {
        failed++;
        continue;
      }
      for (final entry in entries) {
        if (cancellation?.cancelled == true) break;
        if (entry.kind == StorageEntryKind.directory) {
          pending.add(entry.uri);
          continue;
        }
        final format = indexableKind(entry.displayName);
        if (format == null) continue;
        scanned++;
        seen.add('${entry.uri}');
        yield LibraryScanProgress(
            scanned: scanned,
            added: added,
            unchanged: unchanged,
            failed: failed,
            current: entry.displayName);
        try {
          final old = await database.libraryItem('${entry.uri}');
          if (old != null &&
              old.size == entry.size &&
              old.modifiedAt == entry.modifiedAt) {
            if (old.coverKey == null) _scheduleCover(entry, format);
            unchanged++;
            continue;
          }
          String? title, author;
          if (format == ContentKind.epub) {
            final session = await const EpubReaderAdapter().open(
                storage.sourceFor(entry),
                const DetectedFormat(
                    container: ContainerFormat.zip,
                    content: ContentKind.epub,
                    confidence: 1)) as EpubReaderSession;
            title = session.title;
            author = session.author;
            await session.dispose();
          }
          await database.upsertScanned(
              uri: '${entry.uri}',
              name: entry.displayName,
              format: format.name,
              mime: entry.mimeType,
              size: entry.size,
              modified: entry.modifiedAt,
              rootUri: root.uri,
              title: title,
              author: author);
          _scheduleCover(entry, format);
          added++;
        } catch (_) {
          failed++;
        }
      }
    }
    if (cancellation?.cancelled != true) {
      await database.markRootItemsUnavailable(root.uri, seen);
      await database.finishRootScan(root.uri);
    }
    yield LibraryScanProgress(
        scanned: scanned,
        added: added,
        unchanged: unchanged,
        failed: failed,
        done: true,
        cancelled: cancellation?.cancelled == true);
  }

  void _scheduleCover(StorageEntry entry, ContentKind kind) {
    if (readers == null ||
        !{ContentKind.pdf, ContentKind.epub, ContentKind.comic}
            .contains(kind)) {
      return;
    }
    _coverTail =
        _coverTail.then((_) => _generateCover(entry, kind)).catchError((_) {});
  }

  Future<void> _generateCover(StorageEntry entry, ContentKind kind) async {
    final name = entry.displayName.toLowerCase(),
        container = kind == ContentKind.epub || name.endsWith('.cbz')
            ? ContainerFormat.zip
            : name.endsWith('.cbr')
                ? ContainerFormat.rar
                : name.endsWith('.cb7')
                    ? ContainerFormat.sevenZip
                    : ContainerFormat.none,
        session = await readers!.open(storage.sourceFor(entry),
            DetectedFormat(container: container, content: kind, confidence: 1));
    List<int>? bytes;
    if (session is PdfReaderSession) {
      bytes = await session.render(0, width: 300);
    }
    if (session is EpubReaderSession) bytes = session.coverBytes;
    if (session is ComicReaderSession) {
      final page = await session.pages.getPage(0),
          codec = await ui.instantiateImageCodec(page.bytes, targetWidth: 300),
          frame = await codec.getNextFrame(),
          data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      bytes = data?.buffer.asUint8List();
      frame.image.dispose();
      codec.dispose();
    }
    if (bytes != null) {
      final dir = await CacheManager().directory(CacheCategory.covers),
          file = File(
              '${dir.path}/${entry.uri.toString().hashCode.toUnsigned(32)}.png');
      await file.writeAsBytes(bytes);
      await database.updateCover('${entry.uri}', file.path);
    }
    await session.dispose();
  }
}

ContentKind? indexableKind(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return ContentKind.pdf;
  if (n.endsWith('.epub')) return ContentKind.epub;
  if (RegExp(r'\.(cbz|cbr|cb7)$').hasMatch(n)) return ContentKind.comic;
  if (n.endsWith('.txt')) return ContentKind.text;
  if (n.endsWith('.md') || n.endsWith('.markdown')) return ContentKind.markdown;
  return null;
}
