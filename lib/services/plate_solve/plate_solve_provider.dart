import '../../data/models/api_test_result.dart';
import '../../data/models/plate_solve_result.dart';

/// Plate Solve 진행 단계.
enum PlateSolveStage {
  preparing,
  uploading,
  solving,
  calibrating,
  done,
}

/// Plate Solve 진행 상태 메시지.
class PlateSolveProgress {
  const PlateSolveProgress(this.stage, this.message);

  final PlateSolveStage stage;
  final String message;
}

/// Plate Solve 엔진 추상화.
abstract class PlateSolveProvider {
  String get id;

  String get displayName;

  Future<bool> get isConfigured;

  /// 이미지를 업로드하여 Plate Solve를 수행하고 [PlateSolveResult]를 반환한다.
  ///
  /// [centerRa]/[centerDec]/[searchRadiusDeg]가 있으면 서버 검색 범위를
  /// 좁혀 Solve 시간을 줄인다.
  /// [scaleLower]/[scaleUpper]는 `degwidth` 단위 FOV 힌트이다.
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    void Function(PlateSolveProgress progress)? onProgress,
  });

  Future<ApiTestResult> testConnection();
}
