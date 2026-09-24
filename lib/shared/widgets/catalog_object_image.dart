import 'package:flutter/material.dart';

import '../../core/constants/catalog_type.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/catalog_object.dart';
import '../../services/catalog_thumbnail_resolver.dart';
import 'app_file_image.dart';

typedef CatalogImageFallbackBuilder = Widget Function(BuildContext context);

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
    this.fallbackBuilder,
  });

  final CatalogObject object;
  final String? userPhotoPath;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxFit userPhotoFit;
  final BoxFit assetFit;
  final Color backgroundColor;
  final CatalogImageFallbackBuilder? fallbackBuilder;

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
        errorBuilder: (_, _, _) => _assetOrFallback(context),
      ),
      CatalogThumbnailSource.asset => _assetImage(context, selection.path!),
      CatalogThumbnailSource.fallback => _fallback(context),
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

  Widget _assetOrFallback(BuildContext context) {
    final asset = CatalogThumbnailResolver.thumbnailAssetFor(object);
    return asset == null ? _fallback(context) : _assetImage(context, asset);
  }

  Widget _assetImage(BuildContext context, String path) => Image.asset(
    path,
    width: width,
    height: height,
    fit: assetFit,
    filterQuality: FilterQuality.low,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => _fallback(context),
  );

  Widget _fallback(BuildContext context) =>
      fallbackBuilder?.call(context) ??
      Center(
        child: Icon(
          Icons.auto_awesome_outlined,
          color: object.catalog.accentColor,
          size: _fallbackIconSize,
        ),
      );

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
