import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/catalog_exposure_guidance.dart';
import '../../data/models/imaging_suitability_assessment.dart';
import '../../data/models/observation_site.dart';
import '../../data/models/target_imaging_availability.dart';

class CatalogExposureGuidanceSection extends StatelessWidget {
  const CatalogExposureGuidanceSection({
    super.key,
    required this.guidance,
    this.site,
    this.availability,
    this.isAvailabilityLoading = false,
  });

  final CatalogExposureGuidance guidance;
  final ObservationSite? site;
  final TargetImagingAvailability? availability;
  final bool isAvailabilityLoading;

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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '현재 관측지',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _siteLabel,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (isAvailabilityLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ] else if (availability != null) ...[
            const SizedBox(height: 10),
            _buildSummaryGrid(availability!),
          ],
          const Divider(height: 20, color: AppColors.textSecondary),
          const SizedBox(height: 4),
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
            const SizedBox(height: 8),
            _ExposureTimeRow(value: guidance.currentExposureLine!),
          ],
          if (guidance.imagingAssessment != null) ...[
            const SizedBox(height: 8),
            _GuidanceValueRow(
              label: '필터',
              value: guidance.imagingAssessment!.filterMode.label,
            ),
            const SizedBox(height: 6),
            _GuidanceValueRow(
              label: '모자이크',
              value: guidance.imagingAssessment!.mosaicMode.label,
            ),
            const SizedBox(height: 6),
            _GuidanceValueRow(
              label: '예상 결과',
              value:
                  '${guidance.imagingAssessment!.quality.starLabel} ${guidance.imagingAssessment!.quality.label}',
            ),
            const SizedBox(height: 6),
            Text(
              guidance.imagingAssessment!.reason,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          if (guidance.feasibility.showsIdealEnvironment &&
              guidance.idealEnvironmentLabel != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              '권장 환경',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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

  Widget _buildSummaryGrid(TargetImagingAvailability value) {
    final statusColor = value.isAvailableTonight
        ? (value.isDifficultTonight
              ? Colors.orangeAccent
              : Colors.lightGreenAccent)
        : Colors.orangeAccent;
    final items = <Widget>[
      _SummaryValue(
        key: const Key('catalog-today-status'),
        label: '오늘',
        value: value.tonightStatusLabel,
        valueColor: statusColor,
      ),
      if (value.window != null) ...[
        _SummaryValue(
          key: const Key('catalog-available-window'),
          label: '촬영 가능',
          value: _timeRange(
            value.window!.recommendStartTime,
            value.window!.observationEndTime,
          ),
          valueColor: AppColors.messier,
        ),
        _SummaryValue(
          key: const Key('catalog-optimal-window'),
          label: '최적 촬영구간',
          value: _timeRange(
            value.window!.optimalStartTime,
            value.window!.optimalEndTime,
          ),
          valueColor: AppColors.messier,
        ),
      ],
      if (!value.isAvailableTonight && value.primaryReason != null)
        _SummaryValue(label: '사유', value: value.primaryReason!),
      if (guidance.currentRecommendedMinutes != null)
        _SummaryValue(
          key: const Key('catalog-recommended-duration'),
          label: '권장 촬영시간',
          value: '${guidance.currentRecommendedMinutes}분',
          valueColor: AppColors.messier,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 420
            ? 2
            : 1;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          key: const Key('catalog-current-site-summary-grid'),
          spacing: spacing,
          runSpacing: 8,
          children: [
            for (final item in items) SizedBox(width: itemWidth, child: item),
          ],
        );
      },
    );
  }

  String get _siteLabel {
    final value = site;
    if (value == null) return '관측지 정보 없음 · Bortle ${guidance.referenceBortle}';
    return value.bortle == null
        ? value.name
        : '${value.name} · Bortle ${value.bortle}';
  }

  String _timeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    return '${_time(start)} ~ ${_time(end)}';
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _GuidanceValueRow extends StatelessWidget {
  const _GuidanceValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
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
