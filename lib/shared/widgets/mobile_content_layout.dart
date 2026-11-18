import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/pc_design.dart';

/// Apply the PC design language without letting it select desktop geometry
/// or leak to the surrounding shell and other routes.
class MobileContentTheme extends StatelessWidget {
  const MobileContentTheme({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (PcDesign.isStyled(context)) return builder(context);
    return Theme(
      data: AppTheme.mobileContentDark,
      child: Builder(builder: builder),
    );
  }
}

/// Keep the controls visible without letting a short viewport (or keyboard)
/// squeeze the result list offscreen. The header only scrolls if it needs to.
class MobileContentLayout extends StatelessWidget {
  const MobileContentLayout({
    super.key,
    required this.header,
    required this.body,
    this.searching = false,
  });

  final List<Widget> header;
  final Widget body;
  final bool searching;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight * (searching ? 0.65 : 0.56),
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: header,
            ),
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );
}

/// Mobile cards share PC styling but leave room for readable content and
/// larger text, even when a window is too narrow for two tiles.
abstract final class MobileContentGrid {
  static SliverGridDelegateWithFixedCrossAxisCount delegate(
    BuildContext context, {
    required double contentWidth,
    required double childAspectRatio,
    required double minimumCardHeight,
  }) {
    const spacing = AppTheme.spacingSm;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final minWidth = 144.0 * math.max(1.0, scale);
    final columns = ((contentWidth + spacing) / (minWidth + spacing))
        .floor()
        .clamp(1, 4)
        .toInt();
    final tileWidth = (contentWidth - spacing * (columns - 1)) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      mainAxisExtent: math.max(
        minimumCardHeight * math.max(1.0, scale),
        tileWidth / childAspectRatio,
      ),
    );
  }
}
