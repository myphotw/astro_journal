import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/metadata_format.dart';
import '../../../../services/stats_models.dart';

class MonthlyStatsBottomSheet extends StatelessWidget {
  const MonthlyStatsBottomSheet({super.key, required this.detail});

  final MonthlyDetailStats detail;

  static Future<void> show(BuildContext context, MonthlyDetailStats detail) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.cardRadius)),
      ),
      builder: (_) => MonthlyStatsBottomSheet(detail: detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingLg,
          0,
          AppTheme.spacingLg,
          AppTheme.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              detail.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            _DetailRow(
              label: '총 적산시간',
              value: MetadataFormat.formatSeconds(detail.totalIntegrationSeconds),
            ),
            _DetailRow(
              label: '총 촬영횟수',
              value: '${detail.shootCount}회',
            ),
            _DetailRow(
              label: '신규 촬영 대상',
              value: '${detail.newTargetCount}개',
            ),
            _DetailRow(
              label: '평균 적산시간',
              value: MetadataFormat.formatSeconds(detail.averageIntegrationSeconds),
            ),
            _DetailRow(
              label: '가장 많이 촬영한 대상',
              value: detail.mostShotTarget ?? '-',
            ),
            _DetailRow(
              label: '최장 적산 대상',
              value: detail.longestIntegrationTarget ?? '-',
            ),
            if (detail.topThreeTargets.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingSm),
              const Divider(height: 20, color: Color(0x33FFFFFF)),
              const Text(
                'TOP3 촬영 대상',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              for (final target in detail.topThreeTargets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Text(
                        '•',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          target,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
