import '../data/models/api_test_result.dart';
import '../data/models/catalog_object.dart';
import '../data/models/equipment.dart';
import '../data/models/plate_solve_result.dart';
import 'app_logger.dart';
import 'base_api_service.dart';
import 'plate_solve/plate_solve_provider.dart';
import 'plate_solve/targeted_solve_planner.dart';
import 'plate_solve_settings_service.dart';
import 'tc_backend_external_api_client.dart';
import 'tc_backend_plate_solve_service.dart';

/// Plate Solve 기능의 단일 진입점 (UI 로직 미포함).
///
/// Catalog 대상이 있으면 Targeted Solve → 실패 시 radius 확대 → 조건 완화 →
/// Blind Solve 순으로 폴백한다.
class PlateSolveService {
  PlateSolveService(
    this._providers,
    PlateSolveSettingsService settingsService, {
    TargetedSolvePlanner? planner,
    this._backendService,
  }) : _planner = planner ?? TargetedSolvePlanner();

  final List<PlateSolveProvider> _providers;
  final TargetedSolvePlanner _planner;
  final TcBackendPlateSolveService? _backendService;

  static const _tag = 'PlateSolveService';

  PlateSolveProvider get activeProvider => _providers.first;

  TargetedSolvePlanner get planner => _planner;

  /// [target]이 있으면 Targeted 시도 체인, 없으면 Blind 1회.
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    CatalogObject? target,
    Equipment? imagingEquipment,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    int? commonFileId,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    final provider = activeProvider;
    final sw = Stopwatch()..start();

    try {
      // Catalog 대상이 있으면 Targeted 폴백 체인.
      // 대상 없이 좌표만 있으면 단일 Targeted 시도 (하위 호환).
      // 둘 다 없으면 Blind.
      final List<PlateSolveAttempt> attempts;
      if (target != null) {
        attempts = _planner.buildAttempts(
          target: target,
          imagingEquipment: imagingEquipment,
        );
      } else if (centerRa != null && centerDec != null) {
        final scale = (imagingEquipment != null && imagingEquipment.hasFov)
            ? TargetedSolvePlanner.scaleForFov(
                fovWidthDeg: imagingEquipment.fovWidthDegrees!,
                fovHeightDeg: imagingEquipment.fovHeightDegrees!,
              )
            : (
                lower: TargetedSolvePlanner.defaultScaleLower,
                upper: TargetedSolvePlanner.defaultScaleUpper,
              );
        attempts = [
          PlateSolveAttempt(
            mode: PlateSolveMode.targeted,
            label: 'Targeted Solve',
            centerRa: centerRa,
            centerDec: centerDec,
            searchRadiusDeg: searchRadiusDeg ?? 5.0,
            scaleLower: scaleLower ?? scale.lower,
            scaleUpper: scaleUpper ?? scale.upper,
          ),
        ];
      } else {
        attempts = _planner.buildAttempts(imagingEquipment: imagingEquipment);
      }

      final targetName = _planner.targetObjectName(target);
      final inputCoords =
          _planner.resolveInputCoords(target) ??
          (centerRa != null && centerDec != null
              ? (ra: centerRa, dec: centerDec)
              : null);

      if (commonFileId != null) {
        final backend = _backendService;
        if (backend == null) {
          return PlateSolveResult.failure(
            errorMessage: 'Backend Plate Solve 서비스가 준비되지 않았습니다.',
            solver: 'tc_backend',
            solveTimeMs: sw.elapsedMilliseconds,
          );
        }
        final result = await backend.solve(
          commonFileId: commonFileId,
          onProgress: onProgress,
        );
        return result.copyWith(
          targetObject: targetName,
          inputRa: inputCoords?.ra,
          inputDec: inputCoords?.dec,
          solveTimeMs: sw.elapsedMilliseconds,
        );
      }

      AppLogger.info(
        _tag,
        'Plate Solve 시작: $imagePath '
        '(provider=${provider.id}, attempts=${attempts.length}, '
        'target=${targetName ?? '-'})',
      );

      PlateSolveResult? lastFailure;
      for (var i = 0; i < attempts.length; i++) {
        final attempt = attempts[i];
        final attemptLabel = attempts.length > 1
            ? '${attempt.label} (${i + 1}/${attempts.length})'
            : attempt.label;

        onProgress?.call(
          PlateSolveProgress(PlateSolveStage.uploading, '$attemptLabel...'),
        );
        AppLogger.info(
          _tag,
          '시도 ${i + 1}/${attempts.length}: ${attempt.label} '
          'mode=${attempt.mode.name} '
          'ra=${attempt.centerRa} dec=${attempt.centerDec} '
          'radius=${attempt.searchRadiusDeg} '
          'scale=[${attempt.scaleLower},${attempt.scaleUpper}]',
        );

        final result = await provider.solve(
          imagePath: imagePath,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          centerRa: attempt.centerRa,
          centerDec: attempt.centerDec,
          searchRadiusDeg: attempt.searchRadiusDeg,
          scaleLower: attempt.scaleLower,
          scaleUpper: attempt.scaleUpper,
          onProgress: onProgress,
        );

        final enriched = result.copyWith(
          solveMode: attempt.mode,
          targetObject: targetName,
          inputRa: inputCoords?.ra,
          inputDec: inputCoords?.dec,
          solveTimeMs: sw.elapsedMilliseconds,
        );

        if (enriched.success) {
          AppLogger.info(
            _tag,
            'Plate Solve 성공 '
            '(mode=${attempt.mode.name}, ${sw.elapsedMilliseconds}ms)',
          );
          return enriched;
        }

        lastFailure = enriched;
        AppLogger.info(
          _tag,
          'Plate Solve 시도 실패: ${attempt.label} — ${result.errorMessage}',
        );
      }

      AppLogger.info(_tag, 'Plate Solve 최종 실패 (${sw.elapsedMilliseconds}ms)');
      return lastFailure ??
          PlateSolveResult.failure(
            errorMessage: 'Plate Solve에 실패했습니다.',
            solver: provider.id,
            solveTimeMs: sw.elapsedMilliseconds,
          );
    } on ApiException catch (e) {
      AppLogger.error(_tag, e);
      return PlateSolveResult.failure(
        errorMessage: e.message,
        solver: provider.id,
        solveTimeMs: sw.elapsedMilliseconds,
      );
    } on TcBackendExternalApiException catch (e) {
      AppLogger.error(_tag, e);
      final message = switch (e.code) {
        TcBackendExternalApiErrorCode.apiKeyNotConfigured ||
        TcBackendExternalApiErrorCode.providerError ||
        TcBackendExternalApiErrorCode.backendDisabled =>
          'Plate Solve 서비스를 사용할 수 없습니다.',
        _ => e.message,
      };
      return PlateSolveResult.failure(
        errorMessage: message,
        solver: 'tc_backend',
        solveTimeMs: sw.elapsedMilliseconds,
      );
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return PlateSolveResult.failure(
        errorMessage: e.toString(),
        solver: provider.id,
        solveTimeMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<ApiTestResult> testConnection() => activeProvider.testConnection();
}
