import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_site.dart';
import '../viewmodel/light_pollution_map_view_model.dart';

class LightPollutionFavoritesDropdown extends StatelessWidget {
  const LightPollutionFavoritesDropdown({
    super.key,
    required this.viewModel,
    required this.onSelect,
    required this.onUnfavorite,
  });

  final LightPollutionMapViewModel viewModel;
  final void Function(ObservationSite favorite) onSelect;
  final Future<void> Function(ObservationSite favorite) onUnfavorite;

  static const _maxHeight = 320.0;

  @override
  Widget build(BuildContext context) {
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
        itemCount: viewModel.favorites.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          color: AppColors.surface,
        ),
        itemBuilder: (context, index) {
          final favorite = viewModel.favorites[index];
          return _FavoriteTile(
            favorite: favorite,
            onTap: () => onSelect(favorite),
            onUnfavorite: () => onUnfavorite(favorite),
          );
        },
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.onTap,
    required this.onUnfavorite,
  });

  final ObservationSite favorite;
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      favorite.bortle == null
                          ? 'Bortle -'
                          : 'Bortle ${favorite.bortle}',
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
