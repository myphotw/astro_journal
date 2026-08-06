import 'package:flutter/material.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalog_object.dart';
import '../viewmodel/sky_map_view_model.dart';
import 'sky_map_object_symbol.dart';

/// 별자리 이름 탭 시 — 해당 별자리 천체 탐색 목록.
Future<CatalogObject?> showSkyMapConstellationObjectsSheet({
  required BuildContext context,
  required SkyMapViewModel viewModel,
  required String constellationName,
}) {
  return showModalBottomSheet<CatalogObject>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return _ConstellationObjectsSheetBody(
        viewModel: viewModel,
        constellationName: constellationName,
      );
    },
  );
}

class _ConstellationObjectsSheetBody extends StatefulWidget {
  const _ConstellationObjectsSheetBody({
    required this.viewModel,
    required this.constellationName,
  });

  final SkyMapViewModel viewModel;
  final String constellationName;

  @override
  State<_ConstellationObjectsSheetBody> createState() =>
      _ConstellationObjectsSheetBodyState();
}

class _ConstellationObjectsSheetBodyState
    extends State<_ConstellationObjectsSheetBody> {
  late final Set<ConstellationCatalogFilter> _catalogs =
      Set<ConstellationCatalogFilter>.from(ConstellationCatalogFilter.allFilters);
  late final Set<SkyMapObjectTypeFilter> _objectTypes =
      Set<SkyMapObjectTypeFilter>.from(SkyMapObjectTypeFilter.legendFilters);

  void _toggleCatalog(ConstellationCatalogFilter catalog) {
    setState(() {
      if (_catalogs.contains(catalog)) {
        if (_catalogs.length == 1) return;
        _catalogs.remove(catalog);
      } else {
        _catalogs.add(catalog);
      }
    });
  }

  void _toggleObjectType(SkyMapObjectTypeFilter type) {
    setState(() {
      if (_objectTypes.contains(type)) {
        if (_objectTypes.length == 1) return;
        _objectTypes.remove(type);
      } else {
        _objectTypes.add(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final objects = widget.viewModel.objectsInConstellation(
      widget.constellationName,
      catalogs: _catalogs,
      objectTypes: _objectTypes,
    );
    final capturedCount = objects.where((o) => o.captured).length;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.constellationName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '촬영 완료 $capturedCount / 전체 ${objects.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            _chipRow(
              children: [
                for (final chip in ConstellationCatalogFilter.allFilters)
                  _filterChip(
                    label: chip.label,
                    selected: _catalogs.contains(chip),
                    onSelected: () => _toggleCatalog(chip),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _chipRow(
              children: [
                for (final chip in SkyMapObjectTypeFilter.legendFilters)
                  _filterChip(
                    label: chip.label,
                    selected: _objectTypes.contains(chip),
                    symbolKind: chip.symbolKind,
                    onSelected: () => _toggleObjectType(chip),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(height: 1, color: Color(0x22FFFFFF)),
            if (objects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '이 필터에 해당하는 Catalog 천체가 없습니다.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: objects.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    color: Color(0x14FFFFFF),
                  ),
                  itemBuilder: (context, index) {
                    final object = objects[index];
                    return ListTile(
                      dense: true,
                      leading: SkyMapObjectSymbol.fromObjectType(
                        objectType: object.resolvedObjectType,
                        color: object.catalog.accentColor,
                        size: 18,
                      ),
                      title: Text(
                        object.displayName,
                        style: TextStyle(
                          color: object.catalog.accentColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        object.captured ? '✅' : '⬜',
                        style: const TextStyle(fontSize: 16),
                      ),
                      onTap: () => Navigator.of(context).pop(object),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipRow({required List<Widget> children}) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => children[index],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    SkyMapObjectSymbolKind? symbolKind,
  }) {
    return FilterChip(
      avatar: symbolKind == null
          ? null
          : SkyMapObjectSymbol(
              kind: symbolKind,
              color: AppColors.messier,
              size: 13,
            ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.messier.withValues(alpha: 0.28),
      labelStyle: TextStyle(
        color: selected ? AppColors.textPrimary : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => onSelected(),
    );
  }
}
