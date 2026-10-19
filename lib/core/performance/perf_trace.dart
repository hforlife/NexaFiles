import 'package:flutter/foundation.dart';

/// Debug-only timing markers. Calls are compiled out of release logging while
/// the measured work remains unchanged.
abstract final class PerfTrace {
  static Future<T> measure<T>(String label, Future<T> Function() work) async {
    final watch = Stopwatch()..start();
    try {
      return await work();
    } finally {
      assert(() {
        debugPrint('[PERF] $label = ${watch.elapsedMilliseconds} ms');
        return true;
      }());
    }
  }

  static void mark(String label, Stopwatch watch) {
    assert(() {
      debugPrint('[PERF] $label = ${watch.elapsedMilliseconds} ms');
      return true;
    }());
  }
}
