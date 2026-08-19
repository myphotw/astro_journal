import '../../data/models/api_test_result.dart';
import '../../data/models/plate_solve_result.dart';
import 'plate_solve_provider.dart';

/// Marker provider used by the mobile app's NAS-only Plate Solve path.
/// Actual work is delegated by [PlateSolveService] using a backend file ID.
class BackendOnlyPlateSolveProvider implements PlateSolveProvider {
  const BackendOnlyPlateSolveProvider();

  @override
  String get id => 'tc_backend';

  @override
  String get displayName => 'Backend Plate Solve';

  @override
  Future<bool> get isConfigured async => true;

  @override
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
  }) async => PlateSolveResult.failure(
    errorMessage: '서버에 등록된 사진에서만 Plate Solve를 사용할 수 있습니다.',
    solver: id,
  );

  @override
  Future<ApiTestResult> testConnection() async =>
      ApiTestResult.failure(message: '서버 연결 상태에서 Plate Solve 준비 상태를 확인해 주세요.');
}
