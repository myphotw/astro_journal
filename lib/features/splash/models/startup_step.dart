/// 앱 시작 로딩 단계 상태.
enum StartupStepStatus {
  pending,
  loading,
  done,
  error,
}

/// 스플래시 진행 체크리스트 한 항목.
class StartupStep {
  const StartupStep({
    required this.id,
    required this.label,
    this.status = StartupStepStatus.pending,
  });

  final String id;
  final String label;
  final StartupStepStatus status;

  StartupStep copyWith({StartupStepStatus? status}) {
    return StartupStep(
      id: id,
      label: label,
      status: status ?? this.status,
    );
  }

  String get displayLabel {
    switch (status) {
      case StartupStepStatus.done:
        return '✓ $label 로드 완료';
      case StartupStepStatus.loading:
        return '$label 불러오는 중...';
      case StartupStepStatus.error:
        return '✗ $label 로드 실패';
      case StartupStepStatus.pending:
        return label;
    }
  }
}
