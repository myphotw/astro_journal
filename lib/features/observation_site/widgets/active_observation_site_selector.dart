import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/weather_data.dart';
import '../viewmodel/active_observation_site_view_model.dart';

class ActiveObservationSiteSelector extends StatelessWidget {
  const ActiveObservationSiteSelector({
    super.key,
    required this.viewModel,
    required this.onSelectCurrentLocation,
    required this.onSelectSite,
    required this.onOpenDetail,
    required this.onManageSites,
    this.onSaveCurrentLocation,
    this.equipmentName,
    this.embedded = false,
    this.selectorHeight,
    this.activeWeather,
    this.isWeatherLoading = false,
    this.currentLocationBortle,
  });

  static const currentLocationValue = '__current_location__';

  final ActiveObservationSiteViewModel viewModel;
  final Future<void> Function() onSelectCurrentLocation;
  final Future<void> Function(String siteId) onSelectSite;
  final VoidCallback onOpenDetail;
  final VoidCallback onManageSites;
  final VoidCallback? onSaveCurrentLocation;
  final String? equipmentName;
  final bool embedded;
  final double? selectorHeight;
  final WeatherData? activeWeather;
  final bool isWeatherLoading;
  final int? currentLocationBortle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final active = viewModel.active;
        final selectedValue = active.selectedSiteId ?? currentLocationValue;
        final choices = <_SiteChoice>[
          _SiteChoice(
            value: currentLocationValue,
            name: '현재 위치',
            location: '현재 기기 위치',
            bortle: active.isCurrentLocation ? currentLocationBortle : null,
            weather: active.isCurrentLocation ? activeWeather : null,
            weatherLoading: active.isCurrentLocation && isWeatherLoading,
          ),
          ...viewModel.sites.map(
            (site) => _SiteChoice.fromSite(
              site,
              weather: active.selectedSiteId == site.id ? activeWeather : null,
              weatherLoading:
                  active.selectedSiteId == site.id && isWeatherLoading,
            ),
          ),
        ];

        final selector = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '관측지',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              key: const Key('active-observation-site-card'),
              width: double.infinity,
              height: selectorHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.textSecondary.withValues(alpha: 0.22),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('active-observation-site-selector'),
                  value: selectedValue,
                  isExpanded: true,
                  itemHeight: 76,
                  menuMaxHeight: 420,
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: AppColors.surface,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  selectedItemBuilder: (context) => choices
                      .map(
                        (choice) => Align(
                          alignment: Alignment.centerLeft,
                          child: _SelectedSite(choice: choice),
                        ),
                      )
                      .toList(),
                  items: choices
                      .map(
                        (choice) => DropdownMenuItem<String>(
                          value: choice.value,
                          child: _SiteMenuItem(
                            choice: choice,
                            selected: choice.value == selectedValue,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null || value == selectedValue) return;
                    if (value == currentLocationValue) {
                      await onSelectCurrentLocation();
                    } else {
                      await onSelectSite(value);
                    }
                  },
                ),
              ),
            ),
            if (!embedded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      equipmentName?.trim().isNotEmpty == true
                          ? '${viewModel.active.effectiveTrackingMode.label} · ${equipmentName!.trim()}'
                          : viewModel.active.effectiveTrackingMode.label,
                      key: const Key('active-observation-site-summary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (active.isSavedSite)
                    IconButton(
                      key: const Key('open-active-site-detail'),
                      tooltip: '관측지 상세',
                      onPressed: onOpenDetail,
                      icon: const Icon(Icons.chevron_right),
                      visualDensity: VisualDensity.compact,
                    )
                  else if (onSaveCurrentLocation != null)
                    IconButton(
                      key: const Key('save-current-location-as-site'),
                      tooltip: '관측지로 저장',
                      onPressed: onSaveCurrentLocation,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    key: const Key('manage-observation-sites'),
                    tooltip: '관측지 관리',
                    onPressed: onManageSites,
                    icon: const Icon(Icons.tune),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ],
        );

        if (embedded) return selector;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(12), child: selector),
        );
      },
    );
  }
}

class _SiteChoice {
  const _SiteChoice({
    required this.value,
    required this.name,
    required this.location,
    required this.bortle,
    required this.weather,
    required this.weatherLoading,
  });

  factory _SiteChoice.fromSite(
    ObservationSite site, {
    WeatherData? weather,
    bool weatherLoading = false,
  }) => _SiteChoice(
    value: site.id,
    name: site.name,
    location: _locationSummary(site.address),
    bortle: site.bortle,
    weather: weather,
    weatherLoading: weatherLoading,
  );

  final String value;
  final String name;
  final String location;
  final int? bortle;
  final WeatherData? weather;
  final bool weatherLoading;

  String get bortleText => bortle == null ? 'Bortle 미확인' : 'Bortle $bortle';

  String get weatherText {
    if (weatherLoading && weather == null) return '날씨 확인 중';
    final value = weather;
    if (value == null) return '날씨 없음';
    final description = value.description.trim().isEmpty
        ? '구름'
        : value.description.trim();
    return '$description ${value.cloudCoverage}% · '
        '${value.temperature.toStringAsFixed(0)}°C';
  }

  static String _locationSummary(String? address) {
    final value = address?.trim() ?? '';
    if (value.isEmpty) return '위치 미확인';
    return value.split(RegExp(r'\s+')).take(3).join(' ');
  }
}

class _SelectedSite extends StatelessWidget {
  const _SelectedSite({required this.choice});

  final _SiteChoice choice;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        choice.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        '${choice.location} · ${choice.bortleText} · ${choice.weatherText}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
      ),
    ],
  );
}

class _SiteMenuItem extends StatelessWidget {
  const _SiteMenuItem({required this.choice, required this.selected});

  final _SiteChoice choice;
  final bool selected;

  @override
  Widget build(BuildContext context) => Row(
    key: Key('observation-site-option-${choice.value}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 24,
        child: selected
            ? const Icon(
                Icons.check_rounded,
                size: 17,
                color: AppColors.messier,
              )
            : null,
      ),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              choice.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.messier : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              choice.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            Text(
              '${choice.bortleText} · ${choice.weatherText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
