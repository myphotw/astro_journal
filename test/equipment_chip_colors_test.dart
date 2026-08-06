import 'package:astro_journal/core/theme/equipment_chip_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S30 family resolves to blue', () {
    final color = EquipmentChipColors.resolve(
      equipmentId: 's30',
      label: 'Seestar S30 Pro',
    );
    expect(color, const Color(0xFF60A5FA));
  });

  test('S50 family resolves to green', () {
    final color = EquipmentChipColors.resolve(
      equipmentId: 's50',
      label: 'Seestar S50 Pro',
    );
    expect(color, const Color(0xFF34D399));
  });

  test('visual chip resolves to purple', () {
    final color = EquipmentChipColors.resolve(
      equipmentId: 'bcto',
      label: '안시',
      isVisual: true,
    );
    expect(color, EquipmentChipColors.visualDefault);
  });

  test('unknown equipment gets stable fallback color', () {
    final a = EquipmentChipColors.resolve(
      equipmentId: 'custom-1',
      label: 'Custom Scope',
    );
    final b = EquipmentChipColors.resolve(
      equipmentId: 'custom-1',
      label: 'Custom Scope',
    );
    expect(a, b);
  });
}
