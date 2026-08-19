import 'package:flutter/material.dart';

import '../../../data/models/imaging_suitability_assessment.dart';
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
  });

  static const currentLocationValue = '__current_location__';

  final ActiveObservationSiteViewModel viewModel;
  final Future<void> Function() onSelectCurrentLocation;
  final Future<void> Function(String siteId) onSelectSite;
  final VoidCallback onOpenDetail;
  final VoidCallback onManageSites;
  final VoidCallback? onSaveCurrentLocation;
  final String? equipmentName;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final active = viewModel.active;
        final selectedValue = active.selectedSiteId ?? currentLocationValue;
        final equipment = equipmentName?.trim();
        final summary = equipment == null || equipment.isEmpty
            ? active.effectiveTrackingMode.label
            : '${active.effectiveTrackingMode.label} · $equipment';
        return Card(
          key: const Key('active-observation-site-card'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '오늘의 관측지',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: const Key(
                                  'active-observation-site-selector',
                                ),
                                value: selectedValue,
                                isDense: true,
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem(
                                    value: currentLocationValue,
                                    child: Text(
                                      '현재 위치 (임시)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ...viewModel.sites.map(
                                    (site) => DropdownMenuItem(
                                      value: site.id,
                                      child: Text(
                                        site.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == null || value == selectedValue) {
                                    return;
                                  }
                                  if (value == currentLocationValue) {
                                    await onSelectCurrentLocation();
                                  } else {
                                    await onSelectSite(value);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        summary,
                        key: const Key('active-observation-site-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
          ),
        );
      },
    );
  }
}
