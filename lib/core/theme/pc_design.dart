import 'package:flutter/material.dart';

/// Windows gallery palette, shared by the PC shell and its themed screens.
/// Presence of this extension opts shared widgets into PC-only styling.
class PcDesign extends ThemeExtension<PcDesign> {
  const PcDesign();

  static const background = Color(0xFF101722);
  static const card = Color(0xFF192433);
  static const raised = Color(0xFF26364A);
  static const accent = Color(0xFF7898B8);
  static const secondary = Color(0xFF91A9BE);
  static const text = Color(0xFFDCE4ED);
  static const muted = Color(0xFF9AA9B9);
  static const border = Color(0xFF344252);
  static const captured = Color(0xFF91BDB6);

  static bool isActive(BuildContext context) =>
      Theme.of(context).extension<PcDesign>() != null;

  static Color filterBackground(bool selected) => selected ? raised : card;
  static Color filterBorder(bool selected) => selected ? accent : border;
  static Color filterLabel(bool selected) => selected ? text : muted;

  @override
  PcDesign copyWith() => this;

  @override
  PcDesign lerp(covariant PcDesign? other, double t) => this;
}
