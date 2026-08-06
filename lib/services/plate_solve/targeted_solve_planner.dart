import 'dart:math' as math;

import '../../data/models/catalog_object.dart';
import '../../data/models/equipment.dart';
import '../../data/models/plate_solve_result.dart';
import '../celestial_position_service.dart';
import '../equipment/angular_size_resolver.dart';

/// Astrometry.net 업로드에 넘길 단일 시도 파라미터.
class PlateSolveAttempt {
  const PlateSolveAttempt({
    required this.mode,
    required this.label,
    this.centerRa,
    this.centerDec,
    this.searchRadiusDeg,
    this.scaleLower,
    this.scaleUpper,
  });

  final PlateSolveMode mode;
  final String label;
  final double? centerRa;
  final double? centerDec;
  final double? searchRadiusDeg;
  final double? scaleLower;
  final double? scaleUpper;

  bool get isTargeted =>
      mode == PlateSolveMode.targeted &&
      centerRa != null &&
      centerDec != null;
}

/// Catalog 대상·장비 FOV로부터 Targeted / Blind 시도 목록을 만든다.
class TargetedSolvePlanner {
  TargetedSolvePlanner({
    AngularSizeResolver? angularSizeResolver,
  }) : _angularSizeResolver =
            angularSizeResolver ?? const AngularSizeResolver();

  final AngularSizeResolver _angularSizeResolver;

  /// 기본 FOV 스케일 힌트 (장비 정보 없을 때).
  static const defaultScaleLower = 0.25;
  static const defaultScaleUpper = 4.0;

  /// 조건 완화 시 넓은 스케일 힌트.
  static const relaxedScaleLower = 0.1;
  static const relaxedScaleUpper = 15.0;

  /// angular_size(°) + 여유값 → 검색 radius(°).
  ///
  /// 예: 대상 3° → radius 5°.
  static double radiusForAngularSize(double angularSizeDeg) {
    return (angularSizeDeg + 2.0).clamp(2.0, 15.0);
  }

  /// 카메라 FOV(°) → scale_lower / scale_upper (degwidth).
  static ({double lower, double upper}) scaleForFov({
    required double fovWidthDeg,
    required double fovHeightDeg,
  }) {
    final minSide = math.min(fovWidthDeg, fovHeightDeg);
    final maxSide = math.max(fovWidthDeg, fovHeightDeg);
    final lower = (minSide * 0.5).clamp(0.05, 30.0);
    final upper = math.max(maxSide * 2.0, lower + 0.05).clamp(0.1, 40.0);
    return (lower: lower.toDouble(), upper: upper.toDouble());
  }

  /// [target]이 유효한 RA/DEC를 가지면 Targeted 시도 체인, 아니면 Blind 1회.
  ///
  /// 실패 폴백:
  /// 1차 Targeted → 2차 radius 증가 → 3차 조건 완화 → 4차 Blind.
  List<PlateSolveAttempt> buildAttempts({
    CatalogObject? target,
    Equipment? imagingEquipment,
  }) {
    final scale = _resolveScale(imagingEquipment);
    final coords = _resolveCoords(target);

    if (coords == null) {
      return [
        PlateSolveAttempt(
          mode: PlateSolveMode.blind,
          label: 'Blind Solve',
          scaleLower: scale.lower,
          scaleUpper: scale.upper,
        ),
      ];
    }

    final angularSizeDeg = target != null
        ? _angularSizeResolver.resolveDegrees(target)
        : 1.0;
    final baseRadius = radiusForAngularSize(angularSizeDeg);
    final expandedRadius = (baseRadius * 2.0).clamp(baseRadius + 2.0, 20.0);
    final relaxedRadius = (baseRadius * 3.0).clamp(10.0, 30.0);

    return [
      PlateSolveAttempt(
        mode: PlateSolveMode.targeted,
        label: 'Targeted Solve',
        centerRa: coords.ra,
        centerDec: coords.dec,
        searchRadiusDeg: baseRadius,
        scaleLower: scale.lower,
        scaleUpper: scale.upper,
      ),
      PlateSolveAttempt(
        mode: PlateSolveMode.targeted,
        label: 'Targeted Solve (radius 확대)',
        centerRa: coords.ra,
        centerDec: coords.dec,
        searchRadiusDeg: expandedRadius,
        scaleLower: scale.lower,
        scaleUpper: scale.upper,
      ),
      PlateSolveAttempt(
        mode: PlateSolveMode.targeted,
        label: 'Targeted Solve (조건 완화)',
        centerRa: coords.ra,
        centerDec: coords.dec,
        searchRadiusDeg: relaxedRadius,
        scaleLower: relaxedScaleLower,
        scaleUpper: relaxedScaleUpper,
      ),
      const PlateSolveAttempt(
        mode: PlateSolveMode.blind,
        label: 'Blind Solve',
        scaleLower: defaultScaleLower,
        scaleUpper: defaultScaleUpper,
      ),
    ];
  }

  /// Catalog 표시명 (결과 JSON용).
  String? targetObjectName(CatalogObject? target) {
    if (target == null) return null;
    return target.displayName;
  }

  /// Catalog RA/DEC → degrees. 파싱 실패 시 null.
  ({double ra, double dec})? resolveInputCoords(CatalogObject? target) =>
      _resolveCoords(target);

  ({double ra, double dec})? _resolveCoords(CatalogObject? target) {
    if (target == null) return null;
    final raRaw = target.ra.trim();
    final decRaw = target.dec.trim();
    if (raRaw.isEmpty || decRaw.isEmpty || raRaw == '-' || decRaw == '-') {
      return null;
    }
    final raHours = CelestialPositionService.parseRaHours(raRaw);
    final decDeg = CelestialPositionService.parseDecDeg(decRaw);
    // parse 실패 시 0,0 이 될 수 있으므로, 원문이 실제로 0인지 느슨히 허용.
    if (raHours == 0 &&
        decDeg == 0 &&
        !raRaw.contains('0') &&
        !decRaw.contains('0')) {
      return null;
    }
    return (ra: raHours * 15.0, dec: decDeg);
  }

  ({double lower, double upper}) _resolveScale(Equipment? equipment) {
    if (equipment != null &&
        equipment.hasFov &&
        equipment.fovWidthDegrees != null &&
        equipment.fovHeightDegrees != null) {
      return scaleForFov(
        fovWidthDeg: equipment.fovWidthDegrees!,
        fovHeightDeg: equipment.fovHeightDegrees!,
      );
    }
    return (lower: defaultScaleLower, upper: defaultScaleUpper);
  }
}
