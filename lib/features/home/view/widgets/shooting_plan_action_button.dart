import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 추천 대상 카드·목록의 촬영 계획 추가/제거 버튼.
class ShootingPlanActionButton extends StatelessWidget {
  const ShootingPlanActionButton({
    super.key,
    required this.isPlanned,
    required this.isScheduled,
    required this.onToggle,
    this.compact = false,
  });

  final bool isPlanned;
  final bool isScheduled;
  final VoidCallback onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;
    if (!isPlanned) {
      label = '촬영 계획 추가';
      bg = AppColors.ic.withAlpha(48);
      fg = AppColors.ic;
    } else if (isScheduled) {
      label = '계획 등록됨';
      bg = AppColors.textSecondary.withAlpha(40);
      fg = AppColors.textSecondary;
    } else {
      label = '시간 배정 불가';
      bg = AppColors.solar.withAlpha(40);
      fg = AppColors.solar;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 10,
            vertical: compact ? 3 : 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 9 : 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
