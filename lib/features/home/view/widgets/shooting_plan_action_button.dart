import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 추천 대상 카드·목록의 촬영 계획 추가/제거 버튼.
class ShootingPlanActionButton extends StatelessWidget {
  const ShootingPlanActionButton({
    super.key,
    required this.isPlanned,
    required this.onToggle,
    this.compact = false,
  });

  final bool isPlanned;
  final VoidCallback onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = isPlanned ? '계획 등록됨' : '촬영 계획 추가';
    final bg = isPlanned
        ? AppColors.textSecondary.withAlpha(40)
        : AppColors.ic.withAlpha(48);
    final fg = isPlanned ? AppColors.textSecondary : AppColors.ic;

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
