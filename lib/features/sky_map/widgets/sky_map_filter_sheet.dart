import 'package:flutter/material.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../viewmodel/sky_map_view_model.dart';
import 'sky_map_object_symbol.dart';

Future<void> showSkyMapFilterSheet({
  required BuildContext context,
  required SkyMapViewModel viewModel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final filters = viewModel.filters;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 16),
                  const Text(
                    '필터',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Catalog',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in SkyMapFilters.supportedCatalogs)
                        FilterChip(
                          label: Text(type.label),
                          selected: filters.catalogs.contains(type),
                          selectedColor:
                              type.accentColor.withValues(alpha: 0.25),
                          checkmarkColor: type.accentColor,
                          labelStyle: TextStyle(
                            color: filters.catalogs.contains(type)
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          onSelected: (_) => viewModel.toggleCatalog(type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '천체 종류 (범례)',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in SkyMapFilters.supportedObjectTypes)
                        FilterChip(
                          avatar: SkyMapObjectSymbol(
                            kind: type.symbolKind,
                            color: AppColors.messier,
                            size: 14,
                          ),
                          label: Text(type.label),
                          selected: filters.objectTypes.contains(type),
                          selectedColor:
                              AppColors.messier.withValues(alpha: 0.25),
                          checkmarkColor: AppColors.messier,
                          labelStyle: TextStyle(
                            color: filters.objectTypes.contains(type)
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          onSelected: (_) => viewModel.toggleObjectType(type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '별자리 표시',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    value: filters.showConstellations,
                    activeThumbColor: AppColors.messier,
                    onChanged: viewModel.setShowConstellations,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '밝은 별 표시',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: const Text(
                      '1~3등성 (실좌표 성도 카탈로그)',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    value: filters.showBrightStars,
                    activeThumbColor: AppColors.star,
                    onChanged: viewModel.setShowBrightStars,
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
