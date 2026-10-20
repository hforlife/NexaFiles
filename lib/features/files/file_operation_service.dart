import 'dart:async';
import '../../core/errors/app_failure.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/storage/storage_repository.dart';
import 'file_rules.dart';

enum FileOperationKind { copy, move, delete }

class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const OperationCancelled();
  }
}

class OperationCancelled extends AppFailure {
  const OperationCancelled() : super('Opération annulée');
}

class FileOperationProgress {
  const FileOperationProgress({
    required this.kind,
    required this.completed,
    required this.total,
    this.currentName,
    this.done = false,
  });
  final FileOperationKind kind;
  final int completed, total;
  final String? currentName;
  final bool done;
  double? get fraction => total > 0 ? completed / total : null;
}

class OperationResult {
  const OperationResult({required this.succeeded, required this.failed});
  final int succeeded, failed;
}

class FileOperationService {
  FileOperationService(this.storage);
  final StorageRepository storage;
  Stream<FileOperationProgress> transfer({
    required List<StorageEntry> sources,
    required Uri destination,
    required bool move,
    required ConflictPolicy conflict,
    CancellationToken? cancellation,
  }) {
    final controller = StreamController<FileOperationProgress>();
    final token = cancellation ?? CancellationToken();
    () async {
      var completed = 0;
      try {
        for (final source in sources) {
          token.throwIfCancelled();
          controller.add(
            FileOperationProgress(
              kind: move ? FileOperationKind.move : FileOperationKind.copy,
              completed: completed,
              total: sources.length,
              currentName: source.displayName,
            ),
          );
          await _transferEntry(source, destination, conflict, move: move);
          completed++;
        }
        controller.add(
          FileOperationProgress(
            kind: move ? FileOperationKind.move : FileOperationKind.copy,
            completed: completed,
            total: sources.length,
            done: true,
          ),
        );
        await controller.close();
      } catch (e, st) {
        controller.addError(mapFailure(e), st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  /// Copies or moves one entry (file or whole folder) into [destination].
  Future<void> _transferEntry(
    StorageEntry source,
    Uri destination,
    ConflictPolicy policy, {
    required bool move,
  }) async {
    if (source.uri == destination ||
        _looksDescendant(source.uri, destination)) {
      throw const StorageFailure(
        'La destination ne peut pas être située dans la source.',
      );
    }
    final children = await storage.list(destination),
        names = children.map((e) => e.displayName.toLowerCase()).toSet();
    final existing = children
        .where(
          (e) =>
              e.displayName.toLowerCase() == source.displayName.toLowerCase(),
        )
        .firstOrNull;
    var name = source.displayName;
    StorageEntry? replaceTarget;
    if (existing != null && existing.uri == source.uri) {
      // Same folder: moving is a no-op, copying makes a renamed duplicate.
      if (move) return;
      name = keepBothName(name, names);
    } else if (existing != null) {
      switch (policy) {
        case ConflictPolicy.cancel:
          throw const OperationCancelled();
        case ConflictPolicy.skip:
          return;
        case ConflictPolicy.replace:
          // Land under a temporary name first so the old entry is only
          // removed once the new one is complete.
          replaceTarget = existing;
          name = keepBothName('.nexa-copy-${source.displayName}', names);
        case ConflictPolicy.keepBoth:
          name = keepBothName(name, names);
      }
    }
    final created = move
        ? await storage.move(source.uri, destination, targetName: name)
        : await storage.copy(source.uri, destination, targetName: name);
    if (replaceTarget != null) {
      await storage.delete(replaceTarget.uri);
      await storage.rename(created.uri, source.displayName);
    }
  }

  bool _looksDescendant(Uri source, Uri target) {
    final s = Uri.decodeComponent(source.toString()),
        t = Uri.decodeComponent(target.toString());
    return t.startsWith('$s/');
  }

  Future<OperationResult> deleteAll(List<StorageEntry> entries) async {
    var ok = 0, failed = 0;
    for (final entry in entries) {
      try {
        await storage.delete(entry.uri);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    return OperationResult(succeeded: ok, failed: failed);
  }
}
