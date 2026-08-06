import 'dart:ui';



import 'light_pollution_scale.dart';

import 'light_pollution_tile_constants.dart';



/// Maps atlas brightness (mcd/m²) to overlay colors and per-Bortle legend.

class BrightnessColorMapper {

  BrightnessColorMapper._();



  static const List<BrightnessLegendEntry> legendEntries = [

    BrightnessLegendEntry(

      bortle: 1,

      emoji: '🟣',

      label: 'Bortle 1 · 실질적 암야',

      color: Color(0xFF312E81),

    ),

    BrightnessLegendEntry(

      bortle: 2,

      emoji: '🟣',

      label: 'Bortle 2 · 탁월한 암야',

      color: Color(0xFF5B21B6),

    ),

    BrightnessLegendEntry(

      bortle: 3,

      emoji: '🔵',

      label: 'Bortle 3 · 시골 하늘',

      color: Color(0xFF1D4ED8),

    ),

    BrightnessLegendEntry(

      bortle: 4,

      bortle4SubTier: Bortle4SubTier.dark,

      emoji: '🟢',

      label: 'Bortle 4 · 시골·교외 · 어두움',

      color: Color(0xFF064E3B),

    ),

    BrightnessLegendEntry(

      bortle: 4,

      bortle4SubTier: Bortle4SubTier.mid,

      emoji: '🟢',

      label: 'Bortle 4 · 시골·교외 · 보통',

      color: Color(0xFF047857),

    ),

    BrightnessLegendEntry(

      bortle: 4,

      bortle4SubTier: Bortle4SubTier.bright,

      emoji: '🟢',

      label: 'Bortle 4 · 시골·교외 · 밝음',

      color: Color(0xFF10B981),

    ),

    BrightnessLegendEntry(

      bortle: 5,

      emoji: '🟢',

      label: 'Bortle 5 · 준교외',

      color: Color(0xFF65A30D),

    ),

    BrightnessLegendEntry(

      bortle: 6,

      emoji: '🟡',

      label: 'Bortle 6 · 밝은 교외',

      color: Color(0xFFD97706),

    ),

    BrightnessLegendEntry(

      bortle: 7,

      emoji: '🟠',

      label: 'Bortle 7 · 교외·도시',

      color: Color(0xFFEA580C),

    ),

    BrightnessLegendEntry(

      bortle: 8,

      emoji: '🔴',

      label: 'Bortle 8 · 밝은 도시',

      color: Color(0xFFDC2626),

    ),

    BrightnessLegendEntry(

      bortle: 9,

      emoji: '🔴',

      label: 'Bortle 9 · 도시 중심',

      color: Color(0xFF7F1D1D),

    ),

  ];



  static Color colorFor(double artificialMcd) {

    return entryForBrightness(artificialMcd).color;

  }



  static BrightnessLegendEntry legendEntryFor(double artificialMcd) {

    return entryForBrightness(artificialMcd);

  }



  static BrightnessLegendEntry entryForBrightness(double artificialMcd) {

    final bortle = LightPollutionScale.artificialMcdToBortle(artificialMcd);

    if (bortle == 4) {

      final tier =

          LightPollutionScale.bortle4SubTier(artificialMcd) ??

          Bortle4SubTier.mid;

      return entryForBortle4Tier(tier);

    }

    return entryForBortle(bortle);

  }



  static BrightnessLegendEntry entryForBortle(int bortle) {

    if (bortle == 4) {

      return entryForBortle4Tier(Bortle4SubTier.mid);

    }

    final index = legendEntries.indexWhere((entry) => entry.bortle == bortle);

    if (index >= 0) return legendEntries[index];

    return legendEntries.first;

  }



  static BrightnessLegendEntry entryForBortle4Tier(Bortle4SubTier tier) {

    return legendEntries.firstWhere(

      (entry) => entry.bortle == 4 && entry.bortle4SubTier == tier,

    );

  }



  static Color overlayColorFor(double artificialMcd) {
    return colorFor(artificialMcd).withValues(
      alpha: LightPollutionTileConstants.overlayOpacity,
    );
  }
}



class BrightnessLegendEntry {

  const BrightnessLegendEntry({

    required this.bortle,

    required this.emoji,

    required this.label,

    required this.color,

    this.bortle4SubTier,

  });



  final int bortle;

  final Bortle4SubTier? bortle4SubTier;

  final String emoji;

  final String label;

  final Color color;



  String get range => LightPollutionScale.sqmRangeLabel(bortle);



  String get rating => LightPollutionScale.observationRating(bortle);

}


