import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/pc_design.dart';

/// Shared mobile catalog/gallery surface: one image and a short caption.
class MobilePhotoTile extends StatelessWidget {
  const MobilePhotoTile({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  static const gridPadding = EdgeInsets.all(6);
  static const _gap = 5.0;
  static const _captionPadding = EdgeInsets.fromLTRB(7, 4, 7, 5);
  static const _titleSize = 13.0;
  static const _subtitleSize = 11.0;
  static const _lineHeight = 1.25;

  final Widget image;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
    BuildContext context, {
    required double width,
    required double minTileWidth,
    required double imageAspectRatio,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final contentWidth = math.max(0.0, width - gridPadding.horizontal);
    final minWidth =
        minTileWidth * math.max(1.0, scaler.scale(_titleSize) / _titleSize);
    final columns = ((contentWidth + _gap) / (minWidth + _gap)).floor().clamp(
      1,
      4,
    );
    final tileWidth = (contentWidth - _gap * (columns - 1)) / columns;
    final captionHeight =
        ((scaler.scale(_titleSize) + scaler.scale(_subtitleSize)) * _lineHeight)
            .ceilToDouble() +
        _captionPadding.vertical;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: _gap,
      mainAxisSpacing: _gap,
      mainAxisExtent: tileWidth / imageAspectRatio + captionHeight,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: image),
          Padding(
            padding: _captionPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: PcDesign.text,
                    fontSize: _titleSize,
                    height: _lineHeight,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: PcDesign.muted,
                    fontSize: _subtitleSize,
                    height: _lineHeight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
