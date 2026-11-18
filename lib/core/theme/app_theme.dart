import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'pc_design.dart';

class AppTheme {
  AppTheme._();

  static const double cardRadius = 12.0;
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.messier,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.messier,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  /// Base observatory styling for Windows.
  static final ThemeData observatoryDark = _buildObservatoryDark();

  /// Preserves existing Windows geometry and overrides colors only.
  static final ThemeData pcDark = _buildPcDark();

  /// Used only inside the mobile catalog, gallery and planner routes.
  /// Share PC paint and typography, but keep a separate layout signal.
  static final ThemeData mobileContentDark = pcDark.copyWith(
    extensions: const [PcDesign(mobileContent: true)],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  static ThemeData _buildPcDark() {
    final base = observatoryDark;
    return base.copyWith(
      extensions: const [PcDesign()],
      scaffoldBackgroundColor: PcDesign.background,
      canvasColor: PcDesign.card,
      dividerColor: PcDesign.border,
      colorScheme: base.colorScheme.copyWith(
        primary: PcDesign.accent,
        onPrimary: PcDesign.background,
        primaryContainer: PcDesign.raised,
        onPrimaryContainer: PcDesign.text,
        secondary: PcDesign.secondary,
        onSecondary: PcDesign.background,
        secondaryContainer: PcDesign.raised,
        onSecondaryContainer: PcDesign.text,
        tertiary: PcDesign.captured,
        surface: PcDesign.card,
        onSurface: PcDesign.text,
        onSurfaceVariant: PcDesign.muted,
        surfaceContainerLow: PcDesign.card,
        surfaceContainer: PcDesign.card,
        surfaceContainerHigh: PcDesign.raised,
        surfaceContainerHighest: PcDesign.raised,
        outline: PcDesign.accent,
        outlineVariant: PcDesign.border,
        surfaceTint: Colors.transparent,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: PcDesign.text,
        displayColor: PcDesign.text,
      ),
      iconTheme: base.iconTheme.copyWith(color: PcDesign.muted),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: PcDesign.background,
        foregroundColor: PcDesign.text,
        iconTheme: const IconThemeData(color: PcDesign.muted),
        actionsIconTheme: const IconThemeData(color: PcDesign.muted),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: PcDesign.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
          side: BorderSide(color: PcDesign.border),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: PcDesign.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: PcDesign.card,
        modalBackgroundColor: PcDesign.card,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: PcDesign.card,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: PcDesign.raised,
        hintStyle: (base.inputDecorationTheme.hintStyle ?? const TextStyle())
            .copyWith(color: PcDesign.muted),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: PcDesign.text,
        unselectedLabelColor: PcDesign.muted,
        indicatorColor: PcDesign.accent,
        dividerColor: PcDesign.border,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: PcDesign.card,
        selectedColor: PcDesign.raised,
        side: const BorderSide(color: PcDesign.border),
        checkmarkColor: PcDesign.accent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return null;
            return PcDesign.filterBackground(
              states.contains(WidgetState.selected),
            );
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return null;
            return PcDesign.filterLabel(states.contains(WidgetState.selected));
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: PcDesign.border),
          ),
        ),
      ),
    );
  }

  static ThemeData _buildObservatoryDark() {
    final base = dark;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.observatoryBackground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.observatoryPrimary,
        secondary: AppColors.observatoryAccent,
        surface: AppColors.observatorySurface,
        onSurface: AppColors.observatoryText,
        error: AppColors.observatoryDanger,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.observatoryText,
        displayColor: AppColors.observatoryText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.observatoryBackground,
        foregroundColor: AppColors.observatoryText,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.observatorySurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.observatoryBorder),
        ),
      ),
      dividerColor: AppColors.observatoryBorder,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.observatorySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.observatorySurfaceRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
