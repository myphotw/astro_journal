import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';

/// Density and height budget derived from the dashboard pane, not the display.
/// Short or narrow desktop windows keep the compact layout.
class PcDashboardLayout extends InheritedWidget {
  PcDashboardLayout({
    super.key,
    required BoxConstraints viewport,
    required super.child,
  }) : density = math
           .min(
             ((viewport.maxWidth - 1280) / 920).clamp(0.0, 1.0),
             ((viewport.maxHeight - 960) / 360).clamp(0.0, 1.0),
           )
           .toDouble(),
       viewportHeight = viewport.maxHeight.isFinite ? viewport.maxHeight : 0;

  final double density;
  final double viewportHeight;

  static PcDashboardLayout? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PcDashboardLayout>();

  bool get spacious => density > 0;

  // Keep the compact minimums (and page scrolling) in short windows.
  // Only distribute room left after the header, controls and row spacing.
  ({double upper, double lower}) rowHeights(double availableHeight) {
    final upper = viewportHeight < 960 ? 340.0 : 400.0;
    final lower = (viewportHeight * .28).clamp(236.0, 264.0);
    final extra = (availableHeight - upper - lower).clamp(0.0, 430.0) * density;
    return (upper: upper + extra * .54, lower: lower + extra * .46);
  }

  double get sectionGap => AppTheme.spacingSm + density * 8;
  double get horizontalPadding => AppTheme.spacingXl + density * 12;
  double get panelPadding => 12 + 8 * density;
  double get rowGap => 4 + 5 * density;
  double get rowImage => 42 + 14 * density;
  double get rowHeight => 54 + 22 * density;

  @override
  bool updateShouldNotify(PcDashboardLayout oldWidget) =>
      density != oldWidget.density ||
      viewportHeight != oldWidget.viewportHeight;
}
