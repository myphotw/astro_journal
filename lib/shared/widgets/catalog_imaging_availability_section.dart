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
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '등록 관측지 촬영 가능성',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '등록된 관측지가 없습니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }
    final value = availability;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '등록 관측지 촬영 가능성',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '등록 관측지',
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
            const SizedBox(height: 10),
            _AvailabilityDetails(availability: value),
          ],
        ],
      ),
    );
  }
}

class _AvailabilityDetails extends StatelessWidget {
  const _AvailabilityDetails({required this.availability});

  final TargetImagingAvailability availability;

  @override
  Widget build(BuildContext context) {
    final today = _DayAvailabilitySection(
      key: const Key('availability-today-card'),
      dayLabel: '오늘',
      availability: availability,
      observableSeasonLabel: availability.observableSeasonLabel,
      optimalSeasonLabel: availability.optimalSeasonLabel,
    );
    final tomorrow = availability.tomorrow == null
        ? null
        : _DayAvailabilitySection(
            key: const Key('availability-tomorrow-card'),
            dayLabel: '내일',
            availability: availability.tomorrow!,
            weatherExcluded: true,
            observableSeasonLabel: availability.observableSeasonLabel,
            optimalSeasonLabel: availability.optimalSeasonLabel,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600 && tomorrow != null;
        final dayContent = wide
            ? Row(
                key: const Key('catalog-availability-days-row'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: today),
                  const SizedBox(width: 24),
                  Expanded(child: tomorrow),
                ],
              )
            : Column(
                key: const Key('catalog-availability-days-column'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  today,
                  if (tomorrow != null) ...[
                    const Divider(height: 20, color: AppColors.textSecondary),
                    tomorrow,
                  ],
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [dayContent],
        );
      },
    );
  }
}

class _DayAvailabilitySection extends StatelessWidget {
  const _DayAvailabilitySection({
    super.key,
    required this.dayLabel,
    required this.availability,
    this.weatherExcluded = false,
    this.observableSeasonLabel,
    this.optimalSeasonLabel,
  });

  final String dayLabel;
  final TargetImagingAvailability availability;
  final bool weatherExcluded;
  final String? observableSeasonLabel;
  final String? optimalSeasonLabel;

  @override
  Widget build(BuildContext context) {
    final date = availability.referenceDate;
    final window = availability.window;
    final hasReason =
        !availability.isAvailableTonight && availability.primaryReason != null;
    final keyPrefix = dayLabel == '오늘'
        ? 'availability-today'
        : 'availability-tomorrow';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: Row(
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
        ),
        _ValueRow(
          key: ValueKey('$keyPrefix-status'),
          label: '상태',
          value: availability.tonightStatusLabel,
          color: switch (availability.effectiveState) {
            TargetImagingAvailabilityState.sufficientWindow =>
              availability.isDifficultTonight
                  ? Colors.orangeAccent
                  : Colors.lightGreenAccent,
            TargetImagingAvailabilityState.multiNightAccumulation =>
              AppColors.messier,
            TargetImagingAvailabilityState.shortWindow => Colors.orangeAccent,
            TargetImagingAvailabilityState.noObservableWindow =>
              AppColors.textSecondary,
          },
        ),
        if (availability.usableMinutes != null)
          _ValueRow(
            key: ValueKey('$keyPrefix-usable-duration'),
            label: '실제 촬영 가능',
            value: _usableWindowLabel(),
          ),
        if (availability.minimumMinutes != null)
          _ValueRow(
            key: ValueKey('$keyPrefix-minimum-duration'),
            label: '일반 최소 기준',
            value: '${availability.minimumMinutes}분',
            valueWeight: FontWeight.w500,
          ),
        if (availability.recommendedMinutes != null)
          _ValueRow(
            key: ValueKey('$keyPrefix-recommended-duration'),
            label: '권장 촬영시간',
            value: '${availability.recommendedMinutes}분',
            valueWeight: FontWeight.w500,
          ),
        if (availability.hasFramingReference)
          _ValueRow(
            key: ValueKey('$keyPrefix-framing-status'),
            label: '기준 구도',
            value: availability.framingMatched
                ? '동일구도 ${availability.sameFramingMinutes ?? availability.usableMinutes ?? 0}분 누적 가능'
                : '오늘 동일구도 재현 구간 없음',
            color: availability.framingMatched
                ? AppColors.messier
                : AppColors.textSecondary,
          ),
        if (availability.recommendation?.imagingAssessment?.isExtremelyTiny ??
            false)
          const _ValueRow(
            label: '장비',
            value: '선택 장비에서 대상이 매우 작게 표현됨',
            color: Colors.orangeAccent,
            valueWeight: FontWeight.w500,
          ),
        if (availability.weatherAdvisory != null)
          _ValueRow(
            key: ValueKey('$keyPrefix-weather-advisory'),
            label: '기상 의견',
            value: availability.weatherAdvisory!,
            color: AppColors.textSecondary,
            valueWeight: FontWeight.w500,
          ),
        _ValueRow(
          key: ValueKey('$keyPrefix-shooting-window'),
          label: '천문학적 관측 가능',
          value: window == null
              ? '-'
              : _timeRange(
                  window.recommendStartTime,
                  window.observationEndTime,
                ),
          color: window == null ? AppColors.textSecondary : AppColors.messier,
        ),
        _ValueRow(
          key: ValueKey('$keyPrefix-optimal-window'),
          label: '최적 촬영 구간',
          value: window == null
              ? '-'
              : _timeRange(window.optimalStartTime, window.optimalEndTime),
          color: window == null ? AppColors.textSecondary : AppColors.messier,
        ),
        Visibility(
          visible: hasReason,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: _ValueRow(
            label: '사유',
            value: availability.primaryReason ?? '',
            maxLines: 1,
          ),
        ),
        if (observableSeasonLabel != null)
          _ValueRow(
            key: ValueKey(
              dayLabel == '오늘'
                  ? 'availability-today-season'
                  : 'availability-tomorrow-season',
            ),
            label: '촬영 가능 시즌',
            value: observableSeasonLabel!,
            valueWeight: FontWeight.w500,
          ),
        if (optimalSeasonLabel != null)
          _ValueRow(
            label: '최적 촬영 시즌',
            value: optimalSeasonLabel!,
            valueWeight: FontWeight.w500,
          ),
      ],
    );
  }

  String _timeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    String format(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${format(start)} ~ ${format(end)}';
  }

  String _usableWindowLabel() {
    final usableWindow = availability.usableWindow;
    final minutes = availability.usableMinutes;
    if (usableWindow == null) return '${minutes ?? 0}분';
    return '${_timeRange(usableWindow.start, usableWindow.end)} · ${minutes ?? usableWindow.duration.inMinutes}분';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.valueWeight = FontWeight.w600,
    this.maxLines,
  });
  final String label;
  final String value;
  final Color? color;
  final FontWeight valueWeight;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: valueWeight,
            ),
          ),
        ),
      ],
    ),
  );
}
