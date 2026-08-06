import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/catalog_exposure_guidance.dart';

class CatalogExposureGuidanceSection extends StatelessWidget {
  const CatalogExposureGuidanceSection({
    super.key,
    required this.guidance,
  });

  final CatalogExposureGuidance guidance;

  Color _statusColor(CatalogExposureFeasibility feasibility) {
    return switch (feasibility) {
      CatalogExposureFeasibility.recommended => AppColors.messier,
      CatalogExposureFeasibility.feasible => Colors.lightGreenAccent,
      CatalogExposureFeasibility.notRecommended => Colors.orangeAccent,
      CatalogExposureFeasibility.stronglyNotRecommended => Colors.redAccent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(guidance.feasibility);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            guidance.currentEnvironmentLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            guidance.feasibility.statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (guidance.reason != null) ...[
            const SizedBox(height: 6),
            Text(
              guidance.reason!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          if (guidance.currentExposureLine != null) ...[
            const SizedBox(height: 10),
            _ExposureTimeRow(value: guidance.currentExposureLine!),
          ],
          if (guidance.feasibility.showsIdealEnvironment &&
              guidance.idealEnvironmentLabel != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              '권장 환경',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              guidance.idealEnvironmentLabel!,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (guidance.idealExposureLine != null) ...[
              const SizedBox(height: 10),
              _ExposureTimeRow(value: guidance.idealExposureLine!),
            ],
          ],
        ],
      ),
    );
  }
}

class _ExposureTimeRow extends StatelessWidget {
  const _ExposureTimeRow({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 140,
          child: Text(
            '촬영시간 (최소/권장)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
