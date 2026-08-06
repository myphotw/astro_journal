import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/favorite_location_summary.dart';
import '../viewmodel/light_pollution_map_view_model.dart';

class LightPollutionFavoritesDropdown extends StatelessWidget {
  const LightPollutionFavoritesDropdown({
    super.key,
    required this.viewModel,
    required this.onSelect,
    required this.onUnfavorite,
  });

  final LightPollutionMapViewModel viewModel;
  final void Function(FavoriteLocationSummary summary) onSelect;
  final Future<void> Function(FavoriteLocationSummary summary) onUnfavorite;

  static const _maxHeight = 320.0;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoadingFavoriteSummaries &&
        viewModel.favoriteSummaries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (viewModel.favorites.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.spacingSm,
          12,
          AppTheme.spacingSm,
          14,
        ),
        child: Text(
          '등록된 즐겨찾기가 없습니다',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: viewModel.favoriteSummaries.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          color: AppColors.surface,
        ),
        itemBuilder: (context, index) {
          final summary = viewModel.favoriteSummaries[index];
          return _FavoriteSummaryTile(
            summary: summary,
            onTap: () => onSelect(summary),
            onUnfavorite: () => onUnfavorite(summary),
          );
        },
      ),
    );
  }
}

class _FavoriteSummaryTile extends StatelessWidget {
  const _FavoriteSummaryTile({
    required this.summary,
    required this.onTap,
    required this.onUnfavorite,
  });

  final FavoriteLocationSummary summary;
  final VoidCallback onTap;
  final VoidCallback onUnfavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingSm,
            vertical: 12,
          ),
          child: summary.isLoading
              ? const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.favorite.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                summary.bortleLabel,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '☁${summary.cloudCoverage}%',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                summary.starsText,
                                style: const TextStyle(
                                  color: AppColors.solar,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '추천장비 : ${summary.equipmentLabel}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '추천대상 : ${summary.targetsLabel}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '즐겨찾기 해제',
                      onPressed: onUnfavorite,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: const Icon(
                        Icons.star,
                        size: 18,
                        color: AppColors.solar,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
