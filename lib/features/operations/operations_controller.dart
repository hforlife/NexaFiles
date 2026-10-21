import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_failure.dart';
import '../files/file_operation_service.dart';

/// Progress of a background operation, whatever its kind.
class OperationProgress {
  const OperationProgress({
    required this.done,
    required this.total,
    this.current,
    this.finished = false,
  });
  final int done, total;
  final String? current;
  final bool finished;
  double? get fraction => total > 0 ? (done / total).clamp(0, 1) : null;
}

enum OperationKind { copy, move, extract, compress }

enum OperationState { running, done, failed, cancelled }

/// One copy / move / extraction / compression, observable by the UI.
class OperationJob {
  OperationJob({
    required this.id,
    required this.kind,
    required this.title,
    this.destination,
  });
  final int id;
  final OperationKind kind;
  final String title;

  /// Folder holding the result, offered as "Ouvrir" when done.
  final Uri? destination;
  final token = CancellationToken();
  final startedAt = DateTime.now();
  OperationState state = OperationState.running;
  OperationProgress progress = const OperationProgress(done: 0, total: 0);
  String? error;

  bool get running => state == OperationState.running;
}

/// App-wide queue of background operations. They keep running when the
/// screen that started them closes; a foreground service keeps the process
/// alive while the app is in the background.
final operationsProvider = ChangeNotifierProvider<OperationsController>(
  (ref) => OperationsController(),
);

class OperationsController extends ChangeNotifier {
  OperationsController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('nexa_file/operations') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancelAll') cancelAll();
    });
  }

  final MethodChannel _channel;
  final List<OperationJob> jobs = [];
  int _nextId = 1;
  bool _askedPermission = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called with each finished job (done, failed or cancelled).
  final _finished = StreamController<OperationJob>.broadcast();
  Stream<OperationJob> get finished => _finished.stream;

  List<OperationJob> get active => [
    for (final j in jobs)
      if (j.running) j,
  ];
  bool get busy => jobs.any((j) => j.running);

  /// Starts [run] in the background. [onDone] runs after success (e.g. to
  /// refresh a folder), even if the screen that started it is gone.
  OperationJob start({
    required OperationKind kind,
    required String title,
    required Stream<OperationProgress> Function(CancellationToken token) run,
    Uri? destination,
    FutureOr<void> Function()? onDone,
  }) {
    final job = OperationJob(
      id: _nextId++,
      kind: kind,
      title: title,
      destination: destination,
    );
    jobs.insert(0, job);
    // Keep the list short: drop old finished jobs.
    while (jobs.length > 12) {
      final old = jobs.lastWhere((j) => !j.running, orElse: () => jobs.last);
      if (old.running) break;
      jobs.remove(old);
    }
    notifyListeners();
    _askPermissionOnce();
    _syncNotification(force: true);
    late final StreamSubscription<OperationProgress> sub;
    sub = run(job.token).listen(
      (p) {
        job.progress = p;
        notifyListeners();
        _syncNotification();
      },
      onError: (Object e) {
        job.state = e is OperationCancelled || job.token.isCancelled
            ? OperationState.cancelled
            : OperationState.failed;
        job.error = e is AppFailure ? e.userMessage : _clean(e);
        sub.cancel();
        _end(job);
      },
      onDone: () async {
        if (job.state != OperationState.running) return;
        job.state = job.token.isCancelled
            ? OperationState.cancelled
            : OperationState.done;
        if (job.state == OperationState.done) {
          try {
            await onDone?.call();
          } catch (_) {}
        }
        _end(job);
      },
      cancelOnError: true,
    );
    return job;
  }

  void cancel(OperationJob job) {
    if (!job.running) return;
    job.token.cancel();
    notifyListeners();
  }

  void cancelAll() {
    for (final job in active) {
      job.token.cancel();
    }
    notifyListeners();
  }

  void dismiss(OperationJob job) {
    if (job.running) return;
    jobs.remove(job);
    notifyListeners();
  }

  void clearFinished() {
    jobs.removeWhere((j) => !j.running);
    notifyListeners();
  }

  void _end(OperationJob job) {
    notifyListeners();
    _finished.add(job);
    _syncNotification(force: true);
  }

  Future<void> _askPermissionOnce() async {
    if (_askedPermission) return;
    _askedPermission = true;
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// Mirrors progress in the system notification (throttled).
  void _syncNotification({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 500) return;
    _lastNotify = now;
    final running = active;
    try {
      if (running.isEmpty) {
        _channel.invokeMethod('stop').catchError((_) => null);
        return;
      }
      final job = running.first;
      final fraction = job.progress.fraction;
      final more = running.length > 1 ? ' · +${running.length - 1}' : '';
      _channel
          .invokeMethod('update', {
            'title': job.title,
            'text':
                [
                  if (job.progress.total > 0)
                    '${job.progress.done} / ${job.progress.total}',
                  ?job.progress.current,
                ].join(' · ') +
                more,
            'percent': fraction == null ? -1 : (fraction * 100).round(),
          })
          .catchError((_) => null);
    } catch (_) {}
  }

  static String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^\w*(Exception|Error): '), '');

  @override
  void dispose() {
    _finished.close();
    super.dispose();
  }
}

/// Human label of a job kind.
String operationLabel(OperationKind kind) => switch (kind) {
  OperationKind.copy => 'Copie',
  OperationKind.move => 'Déplacement',
  OperationKind.extract => 'Extraction',
  OperationKind.compress => 'Compression',
};
