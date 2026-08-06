import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/metadata_format.dart';
import '../../../../services/stats_models.dart';

class TopTargetsChartCard extends StatelessWidget {
  const TopTargetsChartCard({super.key, required this.targets});

  final List<TopTargetStat> targets;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return const _EmptyChartCard(
        title: 'TOP10 촬영 대상',
        message: '촬영 기록이 없습니다.',
      );
    }

    final maxSeconds = targets
        .map((target) => target.integrationSeconds)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxSeconds <= 0 ? 1.0 : maxSeconds;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'TOP10 촬영 대상',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              '적산시간 기준 내림차순',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            for (final target in targets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HorizontalTargetBar(
                  target: target,
                  maxSeconds: chartMax,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalTargetBar extends StatelessWidget {
  const _HorizontalTargetBar({
    required this.target,
    required this.maxSeconds,
  });

  final TopTargetStat target;
  final double maxSeconds;

  @override
  Widget build(BuildContext context) {
    final ratio = maxSeconds == 0
        ? 0.0
        : (target.integrationSeconds / maxSeconds).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                target.displayName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              MetadataFormat.formatSeconds(target.integrationSeconds),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                target.alias,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${target.shootCount}회',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: AppColors.background.withValues(alpha: 0.5),
            color: const Color(0xFF7986CB).withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

class _EmptyChartCard extends StatelessWidget {
  const _EmptyChartCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
            Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
