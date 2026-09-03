import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/observation_site.dart';
import '../../data/models/target_imaging_availability.dart';

/// Site-aware availability presentation backed by the shared recommendation
/// pipeline. It owns no astronomical policy and is safe to reuse on desktop.
class CatalogImagingAvailabilitySection extends StatelessWidget {
  const CatalogImagingAvailabilitySection({
    super.key,
    required this.sites,
    required this.selectedSite,
    required this.availability,
    required this.isLoading,
    required this.onSelectSite,
  });

  final List<ObservationSite> sites;
  final ObservationSite? selectedSite;
  final TargetImagingAvailability? availability;
  final bool isLoading;
  final ValueChanged<String> onSelectSite;

  @override
  Widget build(BuildContext context) {
    if (sites.isEmpty) {
      return _Card(
        child: const Text(
          '촬영 가능성을 확인하려면 관측지를 먼저 등록해주세요.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    final value = availability;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '촬영 가능성',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '관측지',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          DropdownButton<String>(
            key: const Key('catalog-imaging-availability-site-selector'),
            value: selectedSite?.id,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            items: sites
                .map(
                  (site) => DropdownMenuItem(
                    value: site.id,
                    child: Text(
                      site.bortle == null
                          ? site.name
                          : '${site.name} (Bortle ${site.bortle})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (siteId) {
              if (siteId != null) onSelectSite(siteId);
            },
          ),
          if (isLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ] else if (value != null) ...[
            const SizedBox(height: 12),
            _DayAvailabilitySection(
              dayLabel: '오늘',
              availability: value,
            ),
            if (value.tomorrow != null) ...[
              const Divider(height: 24, color: AppColors.textSecondary),
              _DayAvailabilitySection(
                dayLabel: '내일',
                availability: value.tomorrow!,
                weatherExcluded: true,
              ),
            ],
            if (value.observableSeasonLabel != null)
              _ValueRow(label: '촬영 가능 시즌', value: value.observableSeasonLabel!),
            if (value.optimalSeasonLabel != null)
              _ValueRow(label: '최적 촬영 시즌', value: value.optimalSeasonLabel!),
          ],
        ],
      ),
    );
  }

}

class _DayAvailabilitySection extends StatelessWidget {
  const _DayAvailabilitySection({
    required this.dayLabel,
    required this.availability,
    this.weatherExcluded = false,
  });

  final String dayLabel;
  final TargetImagingAvailability availability;
  final bool weatherExcluded;

  @override
  Widget build(BuildContext context) {
    final date = availability.referenceDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$dayLabel ${date.month}/${date.day}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (weatherExcluded) ...[
              const SizedBox(width: 5),
              const Flexible(
                child: Text(
                  '· 기상정보 미반영',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
        _ValueRow(
          label: '상태',
          value: availability.tonightStatusLabel,
          color: availability.isAvailableTonight
              ? (availability.isDifficultTonight
                    ? Colors.orangeAccent
                    : Colors.lightGreenAccent)
              : Colors.orangeAccent,
        ),
        if (availability.isAvailableTonight && availability.window != null) ...[
          _ValueRow(
            label: '촬영 가능 시간',
            value: _timeRange(
              availability.window!.recommendStartTime,
              availability.window!.observationEndTime,
            ),
          ),
          _ValueRow(
            label: '최적 촬영 구간',
            value: _timeRange(
              availability.window!.optimalStartTime,
              availability.window!.optimalEndTime,
            ),
          ),
        ] else if (availability.primaryReason != null)
          _ValueRow(label: '사유', value: availability.primaryReason!),
      ],
    );
  }

  String _timeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    String format(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${format(start)} ~ ${format(end)}';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
