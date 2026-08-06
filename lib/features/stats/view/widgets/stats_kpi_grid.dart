import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/metadata_format.dart';
import '../../../../services/stats_models.dart';

class StatsKpiGrid extends StatelessWidget {
  const StatsKpiGrid({super.key, required this.kpi});

  final StatsKpiSummary kpi;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppTheme.spacingXs,
      crossAxisSpacing: AppTheme.spacingXs,
      childAspectRatio: 3.8,
      children: [
        _KpiCard(
          label: '총 촬영 횟수',
          value: '${kpi.totalShootCount}회',
          icon: Icons.camera_alt_outlined,
        ),
        _KpiCard(
          label: '총 촬영 대상 수',
          value: '${kpi.totalTargetCount}개',
          icon: Icons.auto_awesome_outlined,
        ),
        _KpiCard(
          label: '총 적산시간',
          value: MetadataFormat.formatSeconds(kpi.totalIntegrationSeconds),
          icon: Icons.timer_outlined,
        ),
        _KpiCard(
          label: '평균 적산시간',
          value: MetadataFormat.formatSeconds(kpi.averageIntegrationSeconds),
          icon: Icons.av_timer_outlined,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingSm,
          vertical: 6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
