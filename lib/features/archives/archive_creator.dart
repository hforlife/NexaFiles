import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../files/file_operation_service.dart';
import '../operations/operations_controller.dart';

/// Formats NexaFiles can create.
enum ArchiveKind {
  zip('ZIP', 'zip', supportsPassword: true),
  tarGz('TAR.GZ', 'tar.gz'),
  sevenZip('7Z', '7z');

  const ArchiveKind(
    this.label,
    this.extension, {
    this.supportsPassword = false,
  });
  final String label, extension;
  final bool supportsPassword;
}

/// Compresses files and folders into a new archive, off the UI thread.
/// ZIP and TAR.GZ are written by a background isolate; 7z by the Android
/// bridge (commons-compress).
class ArchiveCreator {
  static const _native = MethodChannel('nexa_file/archives');
  static final _nativeJobs = <String, StreamController<OperationProgress>>{};
  static bool _listening = false;

  Stream<OperationProgress> create({
    required List<String> sources,
    required String output,
    required ArchiveKind kind,
    String? password,
    required CancellationToken token,
  }) => kind == ArchiveKind.sevenZip
      ? _create7z(sources, output, token)
      : _createInIsolate(sources, output, kind, password, token);

  Stream<OperationProgress> _createInIsolate(
    List<String> sources,
    String output,
    ArchiveKind kind,
    String? password,
    CancellationToken token,
  ) {
    final controller = StreamController<OperationProgress>();
    final port = ReceivePort();
    Isolate? isolate;
    Timer? watch;
    void finish() {
      watch?.cancel();
      port.close();
    }

    controller.onListen = () async {
      isolate = await Isolate.spawn(_worker, [
        port.sendPort,
        sources,
        output,
        kind.index,
        password,
      ]);
      // Cancelling kills the worker and removes the partial archive.
      watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!token.isCancelled) return;
        isolate?.kill(priority: Isolate.immediate);
        finish();
        try {
          File(output).deleteSync();
        } catch (_) {}
        controller.addError(const OperationCancelled());
        controller.close();
      });
    };
    port.listen((message) {
      final m = message as Map;
      switch (m['type']) {
        case 'progress':
          controller.add(
            OperationProgress(
              done: m['done'] as int,
              total: m['total'] as int,
              current: m['current'] as String?,
            ),
          );
        case 'done':
          finish();
          controller.add(
            const OperationProgress(done: 1, total: 1, finished: true),
          );
          controller.close();
        case 'error':
          finish();
          controller.addError(Exception(m['message']));
          controller.close();
      }
    });
    return controller.stream;
  }

  Stream<OperationProgress> _create7z(
    List<String> sources,
    String output,
    CancellationToken token,
  ) {
    if (!_listening) {
      _listening = true;
      _native.setMethodCallHandler((call) async {
        if (call.method != 'progress') return;
        final m = call.arguments as Map;
        _nativeJobs[m['job']]?.add(
          OperationProgress(
            done: m['done'] as int,
            total: m['total'] as int,
            current: m['current'] as String?,
          ),
        );
      });
    }
    final job = '${DateTime.now().microsecondsSinceEpoch}';
    final controller = StreamController<OperationProgress>();
    _nativeJobs[job] = controller;
    final watch = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (token.isCancelled) {
        t.cancel();
        _native.invokeMethod('cancel', {'job': job});
      }
    });
    _native
        .invokeMethod('create7z', {
          'job': job,
          'sources': sources,
          'output': output,
        })
        .then(
          (_) {
            controller.add(
              const OperationProgress(done: 1, total: 1, finished: true),
            );
          },
          onError: (Object e) => controller.addError(
            token.isCancelled ? const OperationCancelled() : e,
          ),
        )
        .whenComplete(() {
          watch.cancel();
          _nativeJobs.remove(job);
          controller.close();
        });
    return controller.stream;
  }
}

/// Isolate entry: [sendPort, sources, output, kindIndex, password].
Future<void> _worker(List<Object?> args) async {
  final send = args[0]! as SendPort;
  final sources = (args[1]! as List).cast<String>();
  final output = args[2]! as String;
  final kind = ArchiveKind.values[args[3]! as int];
  final password = args[4] as String?;
  try {
    // (file, name inside the archive), folders walked recursively.
    final items = <(File, String)>[];
    for (final path in sources) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      final base = p.basename(path);
      if (type == FileSystemEntityType.file) {
        items.add((File(path), base));
      } else if (type == FileSystemEntityType.directory) {
        final files =
            Directory(path)
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          items.add((f, '$base/${p.relative(f.path, from: path)}'));
        }
      }
    }
    final total = items.length;
    void report(int done, String current) => send.send({
      'type': 'progress',
      'done': done,
      'total': total,
      'current': current,
    });
    if (kind == ArchiveKind.zip) {
      final encoder = ZipFileEncoder(
        password: password == null || password.isEmpty ? null : password,
      )..create(output, level: ZipFileEncoder.gzip);
      for (var i = 0; i < items.length; i++) {
        report(i, items[i].$2);
        encoder.addFileSync(items[i].$1, items[i].$2);
      }
      encoder.closeSync();
    } else {
      final tar = '$output.part.tar';
      final encoder = TarFileEncoder()..create(tar);
      for (var i = 0; i < items.length; i++) {
        report(i, items[i].$2);
        await encoder.addFile(items[i].$1, items[i].$2);
      }
      await encoder.close();
      report(total, 'Compression gzip…');
      final input = InputFileStream(tar), out = OutputFileStream(output);
      GZipEncoder().encodeStream(input, out);
      input.closeSync();
      out.closeSync();
      File(tar).deleteSync();
    }
    report(total, '');
    send.send({'type': 'done'});
  } catch (e) {
    try {
      File(output).deleteSync();
    } catch (_) {}
    send.send({'type': 'error', 'message': '$e'});
  }
}
