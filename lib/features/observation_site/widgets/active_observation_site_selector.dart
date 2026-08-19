import 'package:flutter/material.dart';

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
  });

  static const currentLocationValue = '__current_location__';

  final ActiveObservationSiteViewModel viewModel;
  final Future<void> Function() onSelectCurrentLocation;
  final Future<void> Function(String siteId) onSelectSite;
  final VoidCallback onOpenDetail;
  final VoidCallback onManageSites;
  final VoidCallback? onSaveCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final active = viewModel.active;
        final selectedValue = active.selectedSiteId ?? currentLocationValue;
        return Card(
          key: const Key('active-observation-site-card'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '오늘의 관측지',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('active-observation-site-selector'),
                          value: selectedValue,
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(
                              value: currentLocationValue,
                              child: Text('현재 위치 (임시)'),
                            ),
                            ...viewModel.sites.map(
                              (site) => DropdownMenuItem(
                                value: site.id,
                                child: Text(site.name),
                              ),
                            ),
                          ],
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
                    ],
                  ),
                ),
                if (active.isSavedSite)
                  IconButton(
                    key: const Key('open-active-site-detail'),
                    tooltip: '관측지 상세',
                    onPressed: onOpenDetail,
                    icon: const Icon(Icons.chevron_right),
                  )
                else if (onSaveCurrentLocation != null)
                  IconButton(
                    key: const Key('save-current-location-as-site'),
                    tooltip: '관측지로 저장',
                    onPressed: onSaveCurrentLocation,
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                IconButton(
                  key: const Key('manage-observation-sites'),
                  tooltip: '관측지 관리',
                  onPressed: onManageSites,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
