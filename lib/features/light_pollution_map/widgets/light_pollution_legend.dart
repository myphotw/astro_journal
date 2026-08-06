import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../overlay/brightness_color_mapper.dart';

class LightPollutionLegend extends StatefulWidget {
  const LightPollutionLegend({super.key});

  @override
  State<LightPollutionLegend> createState() => _LightPollutionLegendState();
}

class _LightPollutionLegendState extends State<LightPollutionLegend> {
  bool _expanded = true;

  static const double _width = 156;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    // 반드시 고정 폭 — Expanded/무제한 가로 제약이 있으면 화면 전체를 덮어
    // 지도·검색 터치를 가로챈다.
    return SizedBox(
      width: _width,
      child: Material(
        color: surface.withValues(alpha: 0.92),
        elevation: 3,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSm,
              vertical: AppTheme.spacingSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '광해 범례',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: AppTheme.spacingSm),
                  ...BrightnessColorMapper.legendEntries.map(_LegendRow.new),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(this.entry);

  final BrightnessLegendEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 2, right: 6),
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
                Text(
                  entry.range,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
