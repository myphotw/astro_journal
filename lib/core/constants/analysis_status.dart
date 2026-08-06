/// 촬영 대상 자동 분석(EXIF 매칭 → Catalog 검색 → Plate Solve) 진행 상태.
///
/// [ShootingRecord.analysisStatus]에 저장된다. 대상이 이미 사용자 확인을
/// 거쳐 확정된 뒤 저장되므로, 이 상태는 "대상이 맞는지"가 아니라
/// "백그라운드 Plate Solve(WCS) 분석이 어디까지 진행되었는지"를 나타낸다.
///
/// 상태 흐름: `WAITING → PROCESSING → COMPLETED` 또는
/// `WAITING → PROCESSING → FAILED`.
enum AnalysisStatus {
  /// 아직 분석을 시작하지 않음 (백그라운드 Plate Solve 대기 중).
  waiting,

  /// 분석(Plate Solve) 진행 중.
  processing,

  /// 분석 완료 (성공 — 또는 분석이 필요 없어 이미 완료된 상태).
  completed,

  /// 분석 실패.
  failed;

  String get value {
    switch (this) {
      case AnalysisStatus.waiting:
        return 'WAITING';
      case AnalysisStatus.processing:
        return 'PROCESSING';
      case AnalysisStatus.completed:
        return 'COMPLETED';
      case AnalysisStatus.failed:
        return 'FAILED';
    }
  }

  /// 알 수 없는/구버전 데이터는 이미 등록이 끝난 기록이므로 [completed]로
  /// 취급한다 (Gallery에 불필요한 "분석 중" 배지가 뜨지 않도록).
  static AnalysisStatus fromValue(String? value) {
    switch (value) {
      case 'WAITING':
        return AnalysisStatus.waiting;
      case 'PROCESSING':
        return AnalysisStatus.processing;
      case 'FAILED':
        return AnalysisStatus.failed;
      case 'COMPLETED':
        return AnalysisStatus.completed;
      default:
        return AnalysisStatus.completed;
    }
  }

  String get label {
    switch (this) {
      case AnalysisStatus.waiting:
        return '분석 대기 중';
      case AnalysisStatus.processing:
        return '대상 분석 중...';
      case AnalysisStatus.completed:
        return '자동 인식 완료';
      case AnalysisStatus.failed:
        return '대상 미확인';
    }
  }
}
