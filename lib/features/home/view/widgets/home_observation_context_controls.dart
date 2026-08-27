import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/performance_probe.dart';
import '../../../../data/models/equipment.dart';
import '../../../../data/models/imaging_suitability_assessment.dart';
import '../../../../data/models/weather_data.dart';
import '../../../observation_site/viewmodel/active_observation_site_view_model.dart';
import '../../../observation_site/widgets/active_observation_site_selector.dart';

class HomeObservationContextControls extends StatelessWidget {
  const HomeObservationContextControls({
    super.key,
    required this.siteViewModel,
    required this.equipment,
    required this.selectedEquipmentId,
    required this.selectedEquipmentName,
    required this.trackingMode,
    required this.onSelectCurrentLocation,
    required this.onSelectSite,
    required this.onOpenSiteDetail,
    required this.onManageSites,
    required this.onEquipmentChanged,
    required this.onTrackingChanged,
    this.activeWeather,
    this.isWeatherLoading = false,
    this.currentLocationBortle,
    this.onSaveCurrentLocation,
  });

  final ActiveObservationSiteViewModel siteViewModel;
  final List<Equipment> equipment;
  final String? selectedEquipmentId;
  final String? selectedEquipmentName;
  final TrackingMode trackingMode;
  final Future<void> Function() onSelectCurrentLocation;
  final Future<void> Function(String siteId) onSelectSite;
  final VoidCallback onOpenSiteDetail;
  final VoidCallback onManageSites;
  final VoidCallback? onSaveCurrentLocation;
  final ValueChanged<String?> onEquipmentChanged;
  final ValueChanged<TrackingMode> onTrackingChanged;
  final WeatherData? activeWeather;
  final bool isWeatherLoading;
  final int? currentLocationBortle;

  static const double _selectorCardHeight = 58;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.observation_context_controls.build');
    final siteSelector = ActiveObservationSiteSelector(
      viewModel: siteViewModel,
      equipmentName: selectedEquipmentName,
      embedded: true,
      selectorHeight: _selectorCardHeight,
      onSelectCurrentLocation: onSelectCurrentLocation,
      onSelectSite: onSelectSite,
      onOpenDetail: onOpenSiteDetail,
      onManageSites: onManageSites,
      onSaveCurrentLocation: onSaveCurrentLocation,
      activeWeather: activeWeather,
      isWeatherLoading: isWeatherLoading,
      currentLocationBortle: currentLocationBortle,
    );
    final equipmentSelector = _EquipmentSelector(
      equipment: equipment,
      selectedId: selectedEquipmentId,
      onChanged: onEquipmentChanged,
    );

    return LayoutBuilder(
      key: const Key('home-observation-context-controls'),
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            key: const Key('home-context-wide-layout'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: siteSelector),
              const SizedBox(width: AppTheme.spacingSm),
              Expanded(flex: 3, child: equipmentSelector),
              const SizedBox(width: AppTheme.spacingSm),
              SizedBox(
                width: 160,
                child: _TrackingModeSelector(
                  selected: trackingMode,
                  onChanged: onTrackingChanged,
                ),
              ),
            ],
          );
        }

        return Column(
          key: const Key('home-context-compact-layout'),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: siteSelector),
                const SizedBox(width: AppTheme.spacingSm),
                Expanded(child: equipmentSelector),
              ],
            ),
            const SizedBox(height: 6),
            _TrackingModeSelector(
              selected: trackingMode,
              onChanged: onTrackingChanged,
              inline: true,
            ),
          ],
        );
      },
    );
  }
}

class _EquipmentSelector extends StatelessWidget {
  const _EquipmentSelector({
    required this.equipment,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Equipment> equipment;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.equipment_selector.build');
    final hasSelected = equipment.any((item) => item.id == selectedId);
    final choices = <Equipment?>[null, ...equipment];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '장비',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          key: const Key('home-equipment-card'),
          width: double.infinity,
          height: HomeObservationContextControls._selectorCardHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.textSecondary.withValues(alpha: 0.22),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('home-equipment-selector'),
              value: hasSelected ? selectedId : null,
              isExpanded: true,
              itemHeight: 64,
              menuMaxHeight: 380,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              selectedItemBuilder: (context) => choices
                  .map(
                    (item) => Align(
                      alignment: Alignment.centerLeft,
                      child: _EquipmentText(item: item, selected: true),
                    ),
                  )
                  .toList(),
              items: choices
                  .map(
                    (item) => DropdownMenuItem<String?>(
                      value: item?.id,
                      child: Row(
                        key: Key('equipment-option-${item?.id ?? 'auto'}'),
                        children: [
                          SizedBox(
                            width: 24,
                            child:
                                (item?.id == (hasSelected ? selectedId : null))
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 17,
                                    color: AppColors.messier,
                                  )
                                : null,
                          ),
                          Expanded(child: _EquipmentText(item: item)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackingModeSelector extends StatelessWidget {
  const _TrackingModeSelector({
    required this.selected,
    required this.onChanged,
    this.inline = false,
  });

  final TrackingMode selected;
  final ValueChanged<TrackingMode> onChanged;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.tracking_selector.build');
    const label = Text(
      '추적 방식',
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    final selector = SegmentedButton<TrackingMode>(
      segments: const [
        ButtonSegment(
          value: TrackingMode.altAz,
          label: Text('Alt-Az', style: TextStyle(fontSize: 11)),
        ),
        ButtonSegment(
          value: TrackingMode.eq,
          label: Text('EQ', style: TextStyle(fontSize: 11)),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.background
              : AppColors.textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.messier
              : AppColors.background.withValues(alpha: 0.7);
        }),
      ),
    );

    if (inline) {
      return Row(
        key: const Key('home-tracking-mode-selector'),
        children: [
          label,
          const SizedBox(width: AppTheme.spacingSm),
          Expanded(child: selector),
        ],
      );
    }

    return Column(
      key: const Key('home-tracking-mode-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 5),
        SizedBox(width: double.infinity, child: selector),
      ],
    );
  }
}

class _EquipmentText extends StatelessWidget {
  const _EquipmentText({required this.item, this.selected = false});

  final Equipment? item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final equipment = item;
    final title = equipment?.name ?? '자동 선택';
    final detail = equipment == null
        ? '등록 장비 중 적합한 장비 사용'
        : _equipmentSummary(equipment);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }

  static String _equipmentSummary(Equipment equipment) {
    final parts = <String>[];
    if (equipment.focalLengthMm != null) {
      parts.add('${equipment.focalLengthMm!.toStringAsFixed(0)}mm');
    }
    parts.add(equipment.kind.label);
    parts.add('${equipment.purpose.label} 장비');
    if (equipment.hasFov) parts.add('FOV ${equipment.fovLabel}');
    return parts.join(' · ');
  }
}
