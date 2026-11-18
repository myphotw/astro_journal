import 'package:flutter/material.dart';

import '../../core/constants/catalog_type.dart';
import '../../core/constants/object_type.dart';
import '../../core/formatters/catalog_object_display_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/pc_design.dart';
import '../../data/models/catalog_equipment_chips.dart';
import '../../data/models/catalog_object.dart';
import '../../features/sky_map/widgets/sky_map_object_symbol.dart';
import '../../services/catalog_thumbnail_resolver.dart';
import 'catalog_object_image.dart';
import 'catalog_equipment_chips_row.dart';

/// 카탈로그·계절별 촬영 대상 등에서 공통으로 쓰는 천체 카드.
class CatalogObjectCard extends StatelessWidget {
  const CatalogObjectCard({
    super.key,
    required this.object,
    required this.onTap,
    this.thumbnailPath,
    this.equipmentChips = const CatalogEquipmentChips(),
    this.footerText,
  });

  final CatalogObject object;
  final VoidCallback onTap;
  final String? thumbnailPath;
  final CatalogEquipmentChips equipmentChips;

  /// 카드 우측 하단 추가 정보 (예: 계절별 촬영 대상의 최적 월).
  final String? footerText;

  bool get _hasConstellation {
    final value = object.displayConstellation.trim();
    return value.isNotEmpty && value != '-';
  }

  @override
  Widget build(BuildContext context) {
    final pc = PcDesign.isActive(context);
    final color = pc ? PcDesign.secondary : object.catalog.accentColor;
    final thumbnail = CatalogThumbnailResolver.resolve(
      object,
      userPhotoPath: thumbnailPath,
    );
    final hasThumb = thumbnail.hasImage;
    final shootingColor = pc
        ? (object.captured ? PcDesign.captured : PcDesign.muted)
        : object.captured
            ? (hasThumb ? Colors.white : color)
            : (hasThumb ? Colors.white54 : AppColors.textSecondary);

    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasThumb || pc)
                CatalogObjectImage(
                  object: object,
                  userPhotoPath: thumbnailPath,
                  userPhotoFit: BoxFit.cover,
                  assetFit: BoxFit.contain,
                  backgroundColor: hasThumb
                      ? AppColors.background
                      : Colors.transparent,
                  fallbackBuilder: (_) => pc
                      ? _PcCatalogPlaceholder(type: object.resolvedObjectType)
                      : const SizedBox.shrink(),
                ),
              if (hasThumb)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.45, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _CatalogBadge(
                                label: object.catalog.label,
                                color: color,
                                onDarkBackground: hasThumb,
                              ),
                              if (_hasConstellation)
                                _CatalogBadge(
                                  label: object.displayConstellation,
                                  color: pc ? PcDesign.muted : AppColors.textSecondary,
                                  onDarkBackground: hasThumb,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  object.captured
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: shootingColor,
                                  size: 16,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  object.captured ? '촬영' : '미촬영',
                                  style: TextStyle(
                                    color: shootingColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (footerText != null &&
                                footerText!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _CatalogBadge(
                                label: footerText!,
                                color: pc ? PcDesign.accent : AppColors.solar,
                                onDarkBackground: hasThumb,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (!equipmentChips.isEmpty) ...[
                      const SizedBox(height: 4),
                      CatalogEquipmentChipsRow(
                        chips: equipmentChips,
                        onDarkBackground: hasThumb,
                      ),
                    ],
                    const Spacer(),
                    Text(
                      CatalogObjectDisplayFormatter.catalogTitle(object),
                      style: TextStyle(
                        color: pc ? PcDesign.text : (hasThumb ? Colors.white : color),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (CatalogObjectDisplayFormatter.subtitleText(object)
                        .isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacingXs),
                      Text(
                        CatalogObjectDisplayFormatter.subtitleText(object),
                        style: TextStyle(
                          color: pc ? PcDesign.muted : hasThumb
                              ? Colors.white70
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reuses the sky map's vector symbols without changing the image resolver.
class _PcCatalogPlaceholder extends StatelessWidget {
  const _PcCatalogPlaceholder({required this.type});

  final ObjectType type;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.biggest.shortestSide * 0.28)
            .clamp(0.0, 52.0)
            .toDouble();
        final kind = switch (type) {
          ObjectType.planet || ObjectType.dwarfPlanet =>
            SkyMapObjectSymbolKind.planet,
          ObjectType.moon => SkyMapObjectSymbolKind.moon,
          ObjectType.milkyWay => SkyMapObjectSymbolKind.galaxy,
          _ => type.skyMapSymbolKind,
        };

        final widget = switch ((type, kind)) {
          (ObjectType.supernovaRemnant, _) =>
            Icon(Icons.blur_on, size: size, color: PcDesign.accent),
          (_, SkyMapObjectSymbolKind.point) =>
            Icon(Icons.auto_awesome_outlined, size: size, color: PcDesign.accent),
          _ => SkyMapObjectSymbol(kind: kind, color: PcDesign.accent, size: size),
        };
        return Center(child: widget);
      },
    );
  }
}

class _CatalogBadge extends StatelessWidget {
  const _CatalogBadge({
    required this.label,
    required this.color,
    required this.onDarkBackground,
  });

  final String label;
  final Color color;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSm,
        vertical: AppTheme.spacingXs,
      ),
      decoration: BoxDecoration(
        color: onDarkBackground ? Colors.black.withAlpha(120) : color.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onDarkBackground && !PcDesign.isActive(context) ? Colors.white : color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
