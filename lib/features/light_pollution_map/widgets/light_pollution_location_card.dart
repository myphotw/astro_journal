import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_condition.dart';
import '../models/location_weather_info.dart';
import '../overlay/brightness_color_mapper.dart';
import '../overlay/light_pollution_scale.dart';
import 'light_pollution_detail_row.dart';
import 'light_pollution_observation_index.dart';
import 'light_pollution_weather_tab.dart';

enum _LocationCardTab { pollution, weather }

class LightPollutionLocationCard extends StatefulWidget {
  const LightPollutionLocationCard({
    super.key,
    required this.title,
    this.subtitle,
    this.condition,
    this.isLoading = false,
    this.errorMessage,
    this.weatherInfo,
    this.isLoadingWeather = false,
    this.weatherErrorMessage,
    this.onClose,
    this.isFavorited = false,
    this.onFavoriteTap,
    this.width = 188,
  });

  final String title;
  final String? subtitle;
  final ObservationCondition? condition;
  final bool isLoading;
  final String? errorMessage;
  final LocationWeatherInfo? weatherInfo;
  final bool isLoadingWeather;
  final String? weatherErrorMessage;
  final VoidCallback? onClose;
  final bool isFavorited;
  final VoidCallback? onFavoriteTap;
  final double width;

  @override
  State<LightPollutionLocationCard> createState() =>
      _LightPollutionLocationCardState();
}

class _LightPollutionLocationCardState extends State<LightPollutionLocationCard> {
  _LocationCardTab _selectedTab = _LocationCardTab.pollution;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return Material(
      color: surface.withValues(alpha: 0.92),
      elevation: 3,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: SizedBox(
        width: widget.width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CardHeader(
                title: widget.title,
                subtitle: widget.subtitle,
                condition: widget.condition,
                onClose: widget.onClose,
                isFavorited: widget.isFavorited,
                onFavoriteTap: widget.onFavoriteTap,
              ),
              if (widget.errorMessage != null &&
                  _selectedTab == _LocationCardTab.pollution) ...[
                const SizedBox(height: 2),
                Text(
                  widget.errorMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.solar,
                    fontSize: 10,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              _TabSelector(
                selectedTab: _selectedTab,
                onChanged: (tab) => setState(() => _selectedTab = tab),
              ),
              const SizedBox(height: 4),
              if (_selectedTab == _LocationCardTab.pollution)
                _PollutionTabContent(
                  condition: widget.condition,
                  weatherInfo: widget.weatherInfo,
                  isLoading: widget.isLoading,
                  isLoadingWeather: widget.isLoadingWeather,
                  weatherErrorMessage: widget.weatherErrorMessage,
                  width: widget.width,
                )
              else
                LightPollutionWeatherTab(
                  weatherInfo: widget.weatherInfo,
                  isLoading: widget.isLoadingWeather,
                  errorMessage: widget.weatherErrorMessage,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    this.subtitle,
    this.condition,
    this.onClose,
    this.isFavorited = false,
    this.onFavoriteTap,
  });

  final String title;
  final String? subtitle;
  final ObservationCondition? condition;
  final VoidCallback? onClose;
  final bool isFavorited;
  final VoidCallback? onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final brightness = condition?.brightness;
    final legendEntry = brightness != null
        ? BrightnessColorMapper.legendEntryFor(brightness)
        : null;
    final accentColor = legendEntry?.color ?? AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (condition?.bortle != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${condition!.bortle})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onFavoriteTap != null)
              InkWell(
                onTap: onFavoriteTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isFavorited ? Icons.star : Icons.star_border,
                    size: 16,
                    color: isFavorited ? AppColors.solar : AppColors.textSecondary,
                  ),
                ),
              ),
            if (onClose != null)
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({
    required this.selectedTab,
    required this.onChanged,
  });

  final _LocationCardTab selectedTab;
  final ValueChanged<_LocationCardTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabChip(
          label: '광해정보',
          isSelected: selectedTab == _LocationCardTab.pollution,
          onTap: () => onChanged(_LocationCardTab.pollution),
        ),
        const SizedBox(width: 4),
        _TabChip(
          label: '기상정보',
          isSelected: selectedTab == _LocationCardTab.weather,
          onTap: () => onChanged(_LocationCardTab.weather),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.textSecondary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _PollutionTabContent extends StatelessWidget {
  const _PollutionTabContent({
    required this.condition,
    required this.weatherInfo,
    required this.isLoading,
    required this.isLoadingWeather,
    this.weatherErrorMessage,
    required this.width,
  });

  final ObservationCondition? condition;
  final LocationWeatherInfo? weatherInfo;
  final bool isLoading;
  final bool isLoadingWeather;
  final String? weatherErrorMessage;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: width,
        height: 56,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final brightness = condition?.brightness;
    final bortle = condition?.bortle;
    final sqm = condition?.sqm;
    final headline = bortle != null
        ? LightPollutionScale.bortleDisplayLabel(
            bortle,
            artificialMcd: brightness,
          )
        : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        LightPollutionObservationIndexSection(
          weatherInfo: weatherInfo,
          isLoading: isLoadingWeather,
          errorMessage: weatherErrorMessage,
        ),
        const SizedBox(height: 4),
        LightPollutionDetailRow(
          label: 'SQM',
          value: _formatDouble(sqm),
        ),
        LightPollutionDetailRow(
          label: 'Brightness',
          value: _formatDouble(brightness),
        ),
      ],
    );
  }

  static String _formatDouble(double? value) {
    if (value == null) return '-';
    return value.toStringAsFixed(2);
  }
}
