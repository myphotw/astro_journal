import 'package:flutter/material.dart';

/// The Windows palette, also used by selected mobile content screens.
/// The mobile marker keeps shared styling separate from desktop layout.
class PcDesign extends ThemeExtension<PcDesign> {
  const PcDesign({this.mobileContent = false});

  final bool mobileContent;

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
      Theme.of(context).extension<PcDesign>()?.mobileContent == false;

  static bool isMobileContent(BuildContext context) =>
      Theme.of(context).extension<PcDesign>()?.mobileContent == true;

  static bool isStyled(BuildContext context) =>
      Theme.of(context).extension<PcDesign>() != null;

  static Color filterBackground(bool selected) => selected ? raised : card;
  static Color filterBorder(bool selected) => selected ? accent : border;
  static Color filterLabel(bool selected) => selected ? text : muted;

  @override
  PcDesign copyWith() => this;

  @override
  PcDesign lerp(covariant PcDesign? other, double t) => this;
}
