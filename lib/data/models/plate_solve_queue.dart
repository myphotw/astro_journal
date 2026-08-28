import 'plate_solve_result.dart';

/// Canonical status of the durable TC-Backend Plate Solve queue.
enum PlateSolveQueueStatus {
  waiting,
  processing,
  completed,
  failed;

  static PlateSolveQueueStatus? fromJson(Object? value) {
    return switch (value?.toString().trim().toUpperCase()) {
      'WAITING' => PlateSolveQueueStatus.waiting,
      'PROCESSING' => PlateSolveQueueStatus.processing,
      'COMPLETED' => PlateSolveQueueStatus.completed,
      'FAILED' => PlateSolveQueueStatus.failed,
      _ => null,
    };
  }

  String get backendValue => name.toUpperCase();
}

/// Aggregate state returned by `GET /api/astro/plate-solve/summary`.
class PlateSolveSummary {
  const PlateSolveSummary({
    required this.total,
    required this.waiting,
    required this.processing,
    required this.completed,
    required this.failed,
  });

  final int total;
  final int waiting;
  final int processing;
  final int completed;
  final int failed;

  factory PlateSolveSummary.fromJson(Map<String, dynamic> json) {
    return PlateSolveSummary(
      total: _requiredCount(json, 'total'),
      waiting: _requiredCount(json, 'WAITING'),
      processing: _requiredCount(json, 'PROCESSING'),
      completed: _requiredCount(json, 'COMPLETED'),
      failed: _requiredCount(json, 'FAILED'),
    );
  }

  static int _requiredCount(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value.toInt() >= 0) return value.toInt();
    throw FormatException('Plate Solve summary has no valid $key count.');
  }
}

/// Snapshot returned by a Plate Solve submit/status/retry endpoint.
///
/// [jobId] is deliberately opaque; the app never parses or validates it as a
/// UUID so legacy encrypted job identifiers remain compatible.
class PlateSolveJobSnapshot {
  const PlateSolveJobSnapshot({
    required this.jobId,
    required this.commonFileId,
    required this.status,
    this.result,
  });

  final String jobId;
  final int commonFileId;
  final PlateSolveQueueStatus status;
  final PlateSolveResult? result;
}
