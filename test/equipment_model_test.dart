import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Equipment fRatio', () {
    test('computes focal length divided by aperture', () {
      const equipment = Equipment(
        id: '1',
        name: 'BCTO90',
        kind: EquipmentKind.reflector,
        purpose: EquipmentPurpose.visual,
        apertureMm: 90,
        focalLengthMm: 500,
      );

      expect(equipment.fRatio, closeTo(500 / 90, 0.01));
    });

    test('returns null when aperture is missing', () {
      const equipment = Equipment(
        id: '1',
        name: 'Seestar',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        focalLengthMm: 160,
        fovWidthDegrees: 2.24,
        fovHeightDegrees: 3.99,
      );

      expect(equipment.fRatio, isNull);
      expect(equipment.fovLabel, '2.24×3.99°');
    });

    test('fromMap falls back to legacy fov_degrees', () {
      final equipment = Equipment.fromMap({
        'id': '1',
        'name': 'Legacy',
        'equipment_kind': 'smartTelescope',
        'equipment_purpose': 'imaging',
        'is_active': 1,
        'focal_length_mm': 160,
        'fov_degrees': 4.6,
      });

      expect(equipment.fovWidthDegrees, 4.6);
      expect(equipment.fovHeightDegrees, 4.6);
    });
  });

  group('Equipment exposure capability', () {
    const dracoValues = <double>[
      1,
      1.3,
      1.6,
      2,
      2.5,
      3.2,
      4,
      5,
      6,
      8,
      10,
      13,
      15,
      30,
      45,
      60,
      90,
      120,
      180,
      240,
      300,
    ];

    test('round-trips the complete irregular Draco discrete list', () {
      const equipment = Equipment(
        id: 'draco',
        name: 'Draco',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        azExposureCapability: DiscreteExposureCapability(
          valuesSeconds: dracoValues,
        ),
      );

      final restored = Equipment.fromMap(equipment.toMap());
      final capability =
          restored.azExposureCapability as DiscreteExposureCapability;

      expect(capability.valuesSeconds, dracoValues);
      expect(capability.valuesSeconds, containsAll([1.3, 1.6, 2.5, 3.2]));
      expect(restored.eqExposureCapability, isNull);
    });

    test('round-trips independent discrete and range capabilities', () {
      const equipment = Equipment(
        id: 'mixed',
        name: 'Mixed',
        kind: EquipmentKind.other,
        purpose: EquipmentPurpose.imaging,
        azExposureCapability: DiscreteExposureCapability(
          valuesSeconds: [1.3, 2.5],
        ),
        eqExposureCapability: RangeExposureCapability(
          minSeconds: 0.5,
          maxSeconds: 300,
          stepSeconds: 0.25,
        ),
      );

      final restored = Equipment.fromMap(equipment.toMap());
      final az = restored.azExposureCapability as DiscreteExposureCapability;
      final eq = restored.eqExposureCapability as RangeExposureCapability;

      expect(az.valuesSeconds, [1.3, 2.5]);
      expect(eq.minSeconds, 0.5);
      expect(eq.maxSeconds, 300);
      expect(eq.stepSeconds, 0.25);
    });
  });
}
