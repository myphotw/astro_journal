import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/catalog_object.dart';
import '../../services/catalog_thumbnail_resolver.dart';
import 'app_file_image.dart';
import 'catalog_object_symbol.dart';

/// Shared presentation for a user's capture, bundled catalog thumbnail, or
/// the existing placeholder. This widget does not persist either image path.
class CatalogObjectImage extends StatelessWidget {
  const CatalogObjectImage({
    super.key,
    required this.object,
    this.userPhotoPath,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.userPhotoFit = BoxFit.cover,
    this.assetFit = BoxFit.contain,
    this.backgroundColor = AppColors.background,
    this.fillCard = false,
  });

  final CatalogObject object;
  final String? userPhotoPath;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxFit userPhotoFit;
  final BoxFit assetFit;
  final Color backgroundColor;
  final bool fillCard;

  @override
  Widget build(BuildContext context) {
    final selection = CatalogThumbnailResolver.resolve(
      object,
      userPhotoPath: userPhotoPath,
    );
    final child = switch (selection.source) {
      CatalogThumbnailSource.userPhoto => AppFileImage(
        path: selection.path!,
        width: width,
        height: height,
        fit: userPhotoFit,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _assetOrFallback(),
      ),
      CatalogThumbnailSource.asset => _assetImage(selection.path!),
      CatalogThumbnailSource.fallback => _fallback(),
    };

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(color: backgroundColor, child: child),
      ),
    );
  }

  Widget _assetOrFallback() {
    final asset = CatalogThumbnailResolver.thumbnailAssetFor(object);
    return asset == null ? _fallback() : _assetImage(asset);
  }

  Widget _assetImage(String path) => Image.asset(
    path,
    width: width,
    height: height,
    fit: assetFit,
    filterQuality: FilterQuality.low,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => _fallback(),
  );

  Widget _fallback() {
    final kind = CatalogSymbolKind.forObject(object);
    if (!fillCard) {
      return Center(
        child: CatalogObjectSymbol(kind: kind, size: _fallbackIconSize),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.biggest.shortestSide * .28)
            .clamp(0.0, 52.0)
            .toDouble();
        return Center(
          child: CatalogObjectSymbol(kind: kind, size: size),
        );
      },
    );
  }

  double get _fallbackIconSize {
    final resolvedWidth = width;
    final resolvedHeight = height;
    final shortest = resolvedWidth == null
        ? (resolvedHeight ?? 32)
        : resolvedHeight == null
        ? resolvedWidth
        : resolvedWidth < resolvedHeight
        ? resolvedWidth
        : resolvedHeight;
    return (shortest * 0.45).clamp(18, 40).toDouble();
  }
}
