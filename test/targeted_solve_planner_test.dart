import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/services/plate_solve/targeted_solve_planner.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _messier({
  required String id,
  required int number,
  required String ra,
  required String dec,
  String? angularSize,
  double? majorAxis,
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: CatalogType.messier,
    name: id,
    type: '성운',
    constellation: '-',
    ra: ra,
    dec: dec,
    magnitude: '-',
    angularSize: angularSize,
    majorAxis: majorAxis,
  );
}

void main() {
  late TargetedSolvePlanner planner;

  setUp(() {
    planner = TargetedSolvePlanner();
  });

  group('radiusForAngularSize', () {
    test('대상 3° → radius 5°', () {
      expect(TargetedSolvePlanner.radiusForAngularSize(3.0), 5.0);
    });

    test('하한 2°, 상한 15°', () {
      expect(TargetedSolvePlanner.radiusForAngularSize(0.0), 2.0);
      expect(TargetedSolvePlanner.radiusForAngularSize(20.0), 15.0);
    });
  });

  group('scaleForFov', () {
    test('장비 FOV로 scale_low/high 계산', () {
      final scale = TargetedSolvePlanner.scaleForFov(
        fovWidthDeg: 2.24,
        fovHeightDeg: 3.99,
      );
      expect(scale.lower, closeTo(1.12, 0.001));
      expect(scale.upper, closeTo(7.98, 0.001));
    });
  });

  group('M31/M42/M45 Targeted attempts', () {
    test('M31: Targeted 체인 + Blind 폴백, radius≈5°', () {
      final m31 = _messier(
        id: 'M31',
        number: 31,
        ra: '0h42.7m',
        dec: '+41d16m',
        angularSize: "190' × 60'",
      );

      final attempts = planner.buildAttempts(target: m31);
      expect(attempts, hasLength(4));
      expect(attempts[0].mode, PlateSolveMode.targeted);
      expect(attempts[0].searchRadiusDeg, closeTo(5.167, 0.05)); // 3.167+2
      expect(attempts[1].mode, PlateSolveMode.targeted);
      expect(attempts[1].searchRadiusDeg! > attempts[0].searchRadiusDeg!, isTrue);
      expect(attempts[2].mode, PlateSolveMode.targeted);
      expect(attempts[2].scaleLower, TargetedSolvePlanner.relaxedScaleLower);
      expect(attempts[3].mode, PlateSolveMode.blind);
      expect(attempts[3].centerRa, isNull);

      final coords = planner.resolveInputCoords(m31)!;
      expect(coords.ra, closeTo(10.675, 0.05)); // 0h42.7m * 15
      expect(coords.dec, closeTo(41.267, 0.05));
      expect(planner.targetObjectName(m31), 'M31');
    });

    test('M42: Targeted radius = angular_size + 2°', () {
      final m42 = _messier(
        id: 'M42',
        number: 42,
        ra: '5h35.4m',
        dec: '-5d27m',
        angularSize: "85' × 60'",
      );

      final attempts = planner.buildAttempts(target: m42);
      // 85'/60 = 1.4167° + 2 = 3.4167°
      expect(attempts.first.searchRadiusDeg, closeTo(3.417, 0.05));
      expect(planner.targetObjectName(m42), 'M42');
    });

    test('M45: Targeted + 장비 FOV scale', () {
      final m45 = _messier(
        id: 'M45',
        number: 45,
        ra: '3h47.0m',
        dec: '+24d07m',
        angularSize: "120' × 80'",
      );
      const equipment = Equipment(
        id: 'cam-1',
        name: 'Seestar S50',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        fovWidthDegrees: 1.28,
        fovHeightDegrees: 0.72,
      );

      final attempts = planner.buildAttempts(
        target: m45,
        imagingEquipment: equipment,
      );

      expect(attempts.first.mode, PlateSolveMode.targeted);
      expect(attempts.first.scaleLower, closeTo(0.36, 0.001)); // 0.72*0.5
      expect(attempts.first.scaleUpper, closeTo(2.56, 0.001)); // 1.28*2
      expect(attempts.first.searchRadiusDeg, closeTo(4.0, 0.05)); // 2+2
      expect(planner.targetObjectName(m45), 'M45');
    });

    test('대상 없으면 Blind 1회', () {
      final attempts = planner.buildAttempts();
      expect(attempts, hasLength(1));
      expect(attempts.single.mode, PlateSolveMode.blind);
    });

    test('RA/DEC 없으면 Blind', () {
      final broken = _messier(
        id: 'M0',
        number: 0,
        ra: '-',
        dec: '-',
      );
      final attempts = planner.buildAttempts(target: broken);
      expect(attempts.single.mode, PlateSolveMode.blind);
    });
  });
}
