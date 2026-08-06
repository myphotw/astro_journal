import 'package:flutter/material.dart';

import '../../core/theme/equipment_chip_colors.dart';
import '../../data/models/catalog_equipment_chips.dart';

/// 카탈로그 카드·추천 카드 공용 장비 Chip 행.
class CatalogEquipmentChipsRow extends StatelessWidget {
  const CatalogEquipmentChipsRow({
    super.key,
    required this.chips,
    this.onDarkBackground = false,
  });

  final CatalogEquipmentChips chips;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final item in chips.items)
          _CompactEquipmentChip(
            label: item.label,
            equipmentId: item.equipmentId,
            isVisual: item.isVisual,
            onDarkBackground: onDarkBackground,
          ),
      ],
    );
  }
}

class _CompactEquipmentChip extends StatelessWidget {
  const _CompactEquipmentChip({
    required this.label,
    required this.equipmentId,
    required this.isVisual,
    required this.onDarkBackground,
  });

  final String label;
  final String equipmentId;
  final bool isVisual;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final accent = EquipmentChipColors.resolve(
      equipmentId: equipmentId,
      label: label,
      isVisual: isVisual,
    );
    final bg = EquipmentChipColors.background(
      accent,
      onDarkBackground: onDarkBackground,
    );
    final fg = EquipmentChipColors.foreground(
      accent,
      onDarkBackground: onDarkBackground,
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
