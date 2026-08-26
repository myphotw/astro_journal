import 'package:flutter/foundation.dart';

/// Debug-only timing/count probe. Release builds execute only the operation.
abstract final class PerformanceProbe {
  static final Map<String, int> _counts = <String, int>{};

  static int count(String operation) => _counts[operation] ?? 0;

  static void event(String operation, {String? state}) {
    if (!kDebugMode) return;
    final count = (_counts[operation] ?? 0) + 1;
    _counts[operation] = count;
    debugPrint(
      '[PERF] operation=$operation elapsed_ms=0 count=$count${_state(state)}',
    );
  }

  static T measure<T>(String operation, T Function() action, {String? state}) {
    if (!kDebugMode) return action();
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      _record(operation, stopwatch.elapsedMilliseconds, state);
    }
  }

  static Future<T> measureAsync<T>(
    String operation,
    Future<T> Function() action, {
    String? state,
  }) async {
    if (!kDebugMode) return action();
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      _record(operation, stopwatch.elapsedMilliseconds, state);
    }
  }

  @visibleForTesting
  static void reset() => _counts.clear();

  static void _record(String operation, int elapsedMs, String? state) {
    final count = (_counts[operation] ?? 0) + 1;
    _counts[operation] = count;
    debugPrint(
      '[PERF] operation=$operation elapsed_ms=$elapsedMs count=$count${_state(state)}',
    );
  }

  static String _state(String? state) => state == null ? '' : ' state=$state';
}
