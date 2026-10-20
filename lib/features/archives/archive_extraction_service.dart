import 'dart:async';
import 'dart:typed_data';
import '../../core/archives/archive_core.dart';
import '../../core/archives/archive_safety_policy.dart';
import '../../core/storage/storage_repository.dart';
import '../files/file_operation_service.dart';

class ExtractionProgress {
  const ExtractionProgress(
    this.completed,
    this.total,
    this.current, {
    this.done = false,
  });
  final int completed, total;
  final String current;
  final bool done;
  double get fraction => total == 0 ? 0 : completed / total;
}

class ArchiveExtractionService {
  ArchiveExtractionService(
    this.storage, {
    this.policy = const ArchiveSafetyPolicy(),
  });
  final StorageRepository storage;
  final ArchiveSafetyPolicy policy;
  Stream<ExtractionProgress> extract(
    ArchiveSession session,
    Uri destination, {
    ArchiveEntry? only,
    CancellationToken? cancellation,
  }) {
    final controller = StreamController<ExtractionProgress>(),
        token = cancellation ?? CancellationToken();
    () async {
      final created = <Uri>[];
      try {
        final all = await session.listEntries(),
            entries = only == null ? all : [only];
        policy.validate(
          entries.map(
            (e) => (
              path: e.path,
              compressedSize: e.compressedSize,
              uncompressedSize: e.uncompressedSize,
            ),
          ),
        );
        final dirs = <String, Uri>{'': destination};
        var completed = 0;
        for (final entry in entries) {
          token.throwIfCancelled();
          controller.add(
            ExtractionProgress(completed, entries.length, entry.path),
          );
          final parts = entry.path
              .replaceAll('\\', '/')
              .split('/')
              .where((e) => e.isNotEmpty)
              .toList();
          if (parts.isEmpty) continue;
          var parent = destination, path = '';
          for (var i = 0; i < parts.length - (entry.isDirectory ? 0 : 1); i++) {
            path = path.isEmpty ? parts[i] : '$path/${parts[i]}';
            if (!dirs.containsKey(path)) {
              final folder = await storage.createDirectory(parent, parts[i]);
              dirs[path] = folder.uri;
              created.add(folder.uri);
            }
            parent = dirs[path]!;
          }
          if (!entry.isDirectory) {
            final source = await session.openEntry(entry),
                stream = await source.openRead(),
                bytes = <int>[];
            await for (final chunk in stream) {
              token.throwIfCancelled();
              bytes.addAll(chunk);
            }
            final file = await storage.createFile(
              parent,
              parts.last,
              Uint8List.fromList(bytes),
            );
            created.add(file.uri);
          }
          completed++;
        }
        controller.add(
          ExtractionProgress(completed, entries.length, '', done: true),
        );
        await controller.close();
      } catch (e, st) {
        for (final uri in created.reversed) {
          try {
            await storage.delete(uri);
          } catch (_) {}
        }
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }
}
