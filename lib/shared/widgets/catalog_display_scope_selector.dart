import 'package:flutter/material.dart';

import '../../core/constants/famous_celestial_objects.dart';
import 'responsive_filter_chips.dart';

class CatalogDisplayScopeSelector extends StatelessWidget {
  const CatalogDisplayScopeSelector({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  final CatalogDisplayScope scope;
  final ValueChanged<CatalogDisplayScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return FullWidthSegmentedButton<CatalogDisplayScope>(
      segments: const [
        ButtonSegment(value: CatalogDisplayScope.famous, label: Text('유명천체')),
        ButtonSegment(value: CatalogDisplayScope.all, label: Text('전체보기')),
      ],
      selected: {scope},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}
