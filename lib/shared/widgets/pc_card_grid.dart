import 'package:flutter/rendering.dart';

/// Responsive grid for PC catalog and planner cards. Width excludes padding.
abstract final class PcCardGrid {
  static const maxColumns = 8;
  static const minCardWidth = 180.0;
  static const spacing = 12.0;

  static SliverGridDelegateWithFixedCrossAxisCount delegate({
    required double contentWidth,
    required double childAspectRatio,
  }) {
    final columns = ((contentWidth + spacing) / (minCardWidth + spacing))
        .clamp(1, maxColumns)
        .floor();
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
    );
  }
}
