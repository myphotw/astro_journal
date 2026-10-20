import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/sky_map_night_timeline_service.dart';

/// 선택 관측일의 저녁부터 다음 날 새벽까지를 다루는 성도 시간축.
class SkyMapTimeControl extends StatelessWidget {
  const SkyMapTimeControl({
    super.key,
    required this.observationDate,
    required this.observationTime,
    required this.timeline,
    required this.onDateChanged,
    required this.onTimelineMinutesChanged,
    required this.onNowPressed,
  });

  final DateTime observationDate;
  final DateTime observationTime;
  final SkyMapNightTimeline timeline;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<int> onTimelineMinutesChanged;
  final VoidCallback onNowPressed;

  static String formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String formatTimeWithDayOffset(
    DateTime value,
    DateTime observationDate,
  ) {
    final offset = DateTime.utc(value.year, value.month, value.day)
        .difference(
          DateTime.utc(
            observationDate.year,
            observationDate.month,
            observationDate.day,
          ),
        )
        .inDays;
    return offset == 0 ? formatTime(value) : '${formatTime(value)} (+$offset일)';
  }

  static int _snapToTenMinutes(double value, int maximum) =>
      ((value / 10).round() * 10).clamp(0, maximum).toInt();

  Future<void> _showCalendar(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(
        observationDate.year,
        observationDate.month,
        observationDate.day,
      ),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      helpText: '관측 시작일 선택',
    );
    if (selected != null) onDateChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = timeline.totalMinutes;
    final sliderMinutes = timeline.offsetFor(observationTime).toDouble();

    return DecoratedBox(
      key: const ValueKey('sky-map-time-axis'),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                OutlinedButton(
                  key: const ValueKey('sky-map-date-button'),
                  onPressed: () => _showCalendar(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: const BorderSide(color: Color(0x4461758E)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatDate(observationDate)),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    formatTimeWithDayOffset(observationTime, observationDate),
                    key: const ValueKey('sky-map-time-label'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('sky-map-now-button'),
                  onPressed: onNowPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.messier,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('현재'),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _AxisTimeLabel(time: timeline.start),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            top: 10,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                activeTrackColor: AppColors.messier,
                                inactiveTrackColor: const Color(0x4461758E),
                                thumbColor: AppColors.messier,
                                overlayColor: AppColors.messier.withValues(
                                  alpha: 0.14,
                                ),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                              ),
                              child: Slider(
                                key: const ValueKey('sky-map-time-slider'),
                                value: sliderMinutes.clamp(
                                  0,
                                  totalMinutes.toDouble(),
                                ),
                                min: 0,
                                max: totalMinutes.toDouble(),
                                divisions: totalMinutes ~/ 10,
                                label: formatTimeWithDayOffset(
                                  observationTime,
                                  observationDate,
                                ),
                                onChanged: (value) => onTimelineMinutesChanged(
                                  _snapToTenMinutes(value, totalMinutes),
                                ),
                              ),
                            ),
                          ),
                          _TimelineMarker(
                            key: const ValueKey('sky-map-midnight-marker'),
                            fraction: 0.5,
                            label: '00:00',
                            color: AppColors.textPrimary,
                            availableWidth: constraints.maxWidth,
                          ),
                          if (timeline.sunset case final sunset?)
                            _TimelineMarker(
                              key: const ValueKey('sky-map-sunset-marker'),
                              fraction: timeline.fractionFor(sunset),
                              label: '일몰',
                              color: const Color(0xFFE7C579),
                              availableWidth: constraints.maxWidth,
                            ),
                          if (timeline.sunrise case final sunrise?)
                            _TimelineMarker(
                              key: const ValueKey('sky-map-sunrise-marker'),
                              fraction: timeline.fractionFor(sunrise),
                              label: '일출',
                              color: const Color(0xFFE7C579),
                              availableWidth: constraints.maxWidth,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _AxisTimeLabel(time: timeline.end),
              ],
            ),
            if (timeline.usedFallback)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '일몰·일출 없음 · 기본 야간 범위',
                  key: ValueKey('sky-map-night-timeline-fallback'),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AxisTimeLabel extends StatelessWidget {
  const _AxisTimeLabel({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    child: Text(
      SkyMapTimeControl.formatTime(time),
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
    ),
  );
}

class _TimelineMarker extends StatelessWidget {
  const _TimelineMarker({
    super.key,
    required this.fraction,
    required this.label,
    required this.color,
    required this.availableWidth,
  });

  final double fraction;
  final String label;
  final Color color;
  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const markerWidth = 32.0;
    const sliderTrackInset = 24.0;
    final trackWidth = math.max(0.0, availableWidth - sliderTrackInset * 2);
    final left = (sliderTrackInset + fraction * trackWidth - markerWidth / 2)
        .clamp(0.0, math.max(0.0, availableWidth - markerWidth))
        .toDouble();
    return Positioned(
      left: left,
      top: 0,
      width: markerWidth,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(width: 1, height: 8, color: color.withValues(alpha: 0.75)),
        ],
      ),
    );
  }
}
