import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/equipment.dart';
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
}
