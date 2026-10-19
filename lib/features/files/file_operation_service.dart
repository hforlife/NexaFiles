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
  const FileOperationProgress(
      {required this.kind,
      required this.completed,
      required this.total,
      this.currentName,
      this.done = false});
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
  Stream<FileOperationProgress> transfer(
      {required List<StorageEntry> sources,
      required Uri destination,
      required bool move,
      required ConflictPolicy conflict,
      CancellationToken? cancellation}) {
    final controller = StreamController<FileOperationProgress>();
    final token = cancellation ?? CancellationToken();
    () async {
      var completed = 0;
      try {
        for (final source in sources) {
          token.throwIfCancelled();
          controller.add(FileOperationProgress(
              kind: move ? FileOperationKind.move : FileOperationKind.copy,
              completed: completed,
              total: sources.length,
              currentName: source.displayName));
          await _copyEntry(source, destination, conflict, token);
          if (move) {
            await storage.delete(source.uri);
          }
          completed++;
        }
        controller.add(FileOperationProgress(
            kind: move ? FileOperationKind.move : FileOperationKind.copy,
            completed: completed,
            total: sources.length,
            done: true));
        await controller.close();
      } catch (e, st) {
        controller.addError(mapFailure(e), st);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  Future<void> _copyEntry(StorageEntry source, Uri destination,
      ConflictPolicy policy, CancellationToken token) async {
    token.throwIfCancelled();
    if (source.uri == destination ||
        _looksDescendant(source.uri, destination)) {
      throw const StorageFailure(
          'La destination ne peut pas être située dans la source.');
    }
    final children = await storage.list(destination),
        names = children.map((e) => e.displayName.toLowerCase()).toSet();
    var name = source.displayName;
    StorageEntry? replaceTarget;
    final existing = children
        .where((e) => e.displayName.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      switch (policy) {
        case ConflictPolicy.cancel:
          throw const OperationCancelled();
        case ConflictPolicy.skip:
          return;
        case ConflictPolicy.replace:
          replaceTarget = existing;
          name = keepBothName('.nexa-copy-${source.displayName}', names);
          break;
        case ConflictPolicy.keepBoth:
          name = keepBothName(name, names);
          break;
      }
    }
    StorageEntry created;
    if (source.kind == StorageEntryKind.file) {
      created = await storage.copy(source.uri, destination,
          targetName: name == source.displayName ? null : name);
    } else {
      created = await storage.createDirectory(destination, name);
      try {
        for (final child in await storage.list(source.uri)) {
          token.throwIfCancelled();
          await _copyEntry(child, created.uri, policy, token);
        }
      } catch (_) {
        try {
          await storage.delete(created.uri);
        } catch (_) {}
        rethrow;
      }
    }
    if (replaceTarget != null) {
      try {
        await storage.delete(replaceTarget.uri);
        await storage.rename(created.uri, source.displayName);
      } catch (_) {
        rethrow;
      }
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
