import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/pc_design.dart';
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
    this.stackOnNarrow = false,
    this.accentColor,
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
  final bool stackOnNarrow;
  final Color? accentColor;

  static const double _selectorCardHeight = 58;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.observation_context_controls.build');
    final mobile = PcDesign.isMobileContent(context);
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final selectorHeight = mobile && textScale > 1
        ? _selectorCardHeight * textScale
        : _selectorCardHeight;
    final siteSelector = ActiveObservationSiteSelector(
      viewModel: siteViewModel,
      equipmentName: selectedEquipmentName,
      embedded: true,
      selectorHeight: selectorHeight,
      onSelectCurrentLocation: onSelectCurrentLocation,
      onSelectSite: onSelectSite,
      onOpenDetail: onOpenSiteDetail,
      onManageSites: onManageSites,
      onSaveCurrentLocation: onSaveCurrentLocation,
      activeWeather: activeWeather,
      isWeatherLoading: isWeatherLoading,
      currentLocationBortle: currentLocationBortle,
      accentColor: accentColor,
    );
    final equipmentSelector = _EquipmentSelector(
      equipment: equipment,
      selectedId: selectedEquipmentId,
      onChanged: onEquipmentChanged,
      accentColor: accentColor,
      height: selectorHeight,
    );

    return LayoutBuilder(
      key: const Key('home-observation-context-controls'),
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            700 * (mobile && textScale > 1 ? textScale : 1)) {
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
                  accentColor: accentColor,
                ),
              ),
            ],
          );
        }

        if (stackOnNarrow ||
            (mobile && constraints.maxWidth < 500 * textScale)) {
          return Column(
            key: const Key('home-context-compact-layout'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              siteSelector,
              const SizedBox(height: AppTheme.spacingSm),
              equipmentSelector,
              const SizedBox(height: AppTheme.spacingSm),
              _TrackingModeSelector(
                selected: trackingMode,
                onChanged: onTrackingChanged,
                accentColor: accentColor,
                inline: !mobile,
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
              accentColor: accentColor,
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
    required this.height,
    this.accentColor,
  });

  final List<Equipment> equipment;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final Color? accentColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.equipment_selector.build');
    final hasSelected = equipment.any((item) => item.id == selectedId);
    final choices = <Equipment?>[null, ...equipment];
    final mobile = PcDesign.isMobileContent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '장비',
          style: TextStyle(
            color: mobile ? PcDesign.muted : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          key: const Key('home-equipment-card'),
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: mobile
                ? PcDesign.raised
                : AppColors.background.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: mobile
                  ? PcDesign.border
                  : AppColors.textSecondary.withValues(alpha: 0.22),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              key: const Key('home-equipment-selector'),
              value: hasSelected ? selectedId : null,
              isExpanded: true,
              itemHeight: mobile ? null : 64,
              menuMaxHeight: 380,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: mobile ? PcDesign.card : AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              selectedItemBuilder: (context) => choices
                  .map(
                    (item) => Align(
                      alignment: Alignment.centerLeft,
                      child: _EquipmentText(item: item),
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
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 17,
                                    color: accentColor ?? AppColors.messier,
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
    this.accentColor,
  });

  final TrackingMode selected;
  final ValueChanged<TrackingMode> onChanged;
  final bool inline;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event('widget.tracking_selector.build');
    final mobile = PcDesign.isMobileContent(context);
    final label = Text(
      '추적 방식',
      style: TextStyle(
        color: mobile ? PcDesign.muted : AppColors.textSecondary,
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
      style: mobile
          ? null
          : ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? AppColors.background
                    : AppColors.textPrimary;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? (accentColor ?? AppColors.messier)
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
  const _EquipmentText({required this.item});

  final Equipment? item;

  @override
  Widget build(BuildContext context) {
    final equipment = item;
    final mobile = PcDesign.isMobileContent(context);
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
            color: mobile ? PcDesign.text : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mobile ? PcDesign.muted : AppColors.textSecondary,
            fontSize: 10,
          ),
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
