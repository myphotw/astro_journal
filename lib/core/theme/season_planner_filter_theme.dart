import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 계절별 촬영대상 필터 칩 — 선택 여부가 한눈에 보이도록 통일 색상.
class SeasonPlannerFilterTheme {
  SeasonPlannerFilterTheme._();

  /// 선택 강조색 (Cyan Accent).
  static const Color selectedAccent = Color(0xFF4DD0E1);

  /// 미선택 배경 (Dark Grey / Surface Variant 톤).
  static const Color unselectedBackground = Color(0xFF1E293B);
  static const Color unselectedBorder = Color(0xFF475569);

  static ChipColors colorsFor({required bool selected}) {
    if (!selected) {
      return const ChipColors(
        background: unselectedBackground,
        border: unselectedBorder,
        label: AppColors.textSecondary,
      );
    }

    return ChipColors(
      background: Color.alphaBlend(
        selectedAccent.withValues(alpha: 0.22),
        AppColors.surface,
      ),
      border: selectedAccent.withValues(alpha: 0.85),
      label: AppColors.textPrimary,
    );
  }
}

class ChipColors {
  const ChipColors({
    required this.background,
    required this.border,
    required this.label,
  });

  final Color background;
  final Color border;
  final Color label;
}
