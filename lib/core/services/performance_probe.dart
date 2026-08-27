import 'package:flutter/foundation.dart';

/// Debug-only timing/count probe. Release builds execute only the operation.
abstract final class PerformanceProbe {
  static final Map<String, int> _counts = <String, int>{};
  static final Map<String, int> _totalElapsedMs = <String, int>{};
  static final Map<String, int> _maxElapsedMs = <String, int>{};

  static int count(String operation) => _counts[operation] ?? 0;

  static PerformanceProbeStats stats(String operation) => PerformanceProbeStats(
    count: count(operation),
    totalElapsedMs: _totalElapsedMs[operation] ?? 0,
    maxElapsedMs: _maxElapsedMs[operation] ?? 0,
  );

  static void event(String operation, {String? state}) {
    if (!kDebugMode) return;
    _record(operation, 0, state);
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

  static void record(String operation, Duration elapsed, {String? state}) {
    if (!kDebugMode) return;
    _record(operation, elapsed.inMilliseconds, state);
  }

  @visibleForTesting
  static void reset() {
    _counts.clear();
    _totalElapsedMs.clear();
    _maxElapsedMs.clear();
  }

  static void _record(String operation, int elapsedMs, String? state) {
    final count = (_counts[operation] ?? 0) + 1;
    _counts[operation] = count;
    _totalElapsedMs[operation] = (_totalElapsedMs[operation] ?? 0) + elapsedMs;
    final previousMax = _maxElapsedMs[operation] ?? 0;
    final isNewSignificantMax = elapsedMs >= 50 && elapsedMs > previousMax;
    if (elapsedMs > previousMax) _maxElapsedMs[operation] = elapsedMs;
    if (count != 1 && count % 100 != 0 && !isNewSignificantMax) return;
    debugPrint(
      '[PERF] operation=$operation elapsed_ms=$elapsedMs count=$count '
      'max_ms=${_maxElapsedMs[operation] ?? 0}${_state(state)}',
    );
  }

  static String _state(String? state) => state == null ? '' : ' state=$state';
}

class PerformanceProbeStats {
  const PerformanceProbeStats({
    required this.count,
    required this.totalElapsedMs,
    required this.maxElapsedMs,
  });

  final int count;
  final int totalElapsedMs;
  final int maxElapsedMs;

  double get averageElapsedMs => count == 0 ? 0 : totalElapsedMs / count;
}
