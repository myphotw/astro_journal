import 'dart:math' as math;

/// Converts World Atlas artificial zenith luminance (mcd/m²) to SQM / Bortle.
///
/// Bortle class uses Falchi 2016 Table 1 ratio bins (14 levels) mapped across
/// Bortle 1–9 for finer regional gradation than the coarse SQM class table.
/// Urban ratio floors keep inner cities at class 8–9.
class LightPollutionScale {
  LightPollutionScale._();

  /// Falchi 2016 / lightpollutionmap.info natural zenith reference (174 μcd/m²).
  static const double falchiNaturalReferenceMcd = 0.174;

  /// Natural background for SQM prediction (Loss of the Night blog, S=1.15).
  static const double sqmNaturalBackgroundMcd = 0.271;

  /// Ratio at Falchi bin 14 (urban core); used only for minimum Bortle 9.
  static const double _urbanCoreRatio = 20.5;

  /// Ratio at Falchi bin 13; used only for minimum Bortle 8.
  static const double _brightCityRatio = 10.2;

  /// SQM conversion denominator (mcd/m² basis).
  static const double _sqmDenominator = 108000000.0;

  /// Falchi Table 1 ratio thresholds (artificial / 174 μcd/m²), ascending.
  static const List<double> falchiRatioThresholds = [
    0.01,
    0.02,
    0.04,
    0.08,
    0.16,
    0.32,
    0.64,
    1.28,
    2.56,
    5.12,
    10.2,
    20.5,
    41,
  ];

  /// World Atlas 14-bin index → Bortle 1–9 (finer steps than SQM table alone).
  static const List<int> falchiBinToBortle = [
    1, // bin 1  ratio < 0.01
    1, // bin 2
    2, // bin 3
    2, // bin 4
    3, // bin 5
    4, // bin 6
    4, // bin 7
    4, // bin 8
    4, // bin 9  — rural valleys e.g. Gurye
    5, // bin 10
    6, // bin 11
    7, // bin 12
    8, // bin 13
    9, // bin 14 — urban core
  ];

  /// Predicted SQM reading (mag/arcsec²) from total zenith luminance (mcd/m²).
  static double totalMcdToSqmMag(double totalMcd) {
    if (totalMcd <= 0) return 25;
    return -2.5 * math.log(totalMcd / _sqmDenominator) / math.ln10;
  }

  /// SQM mag/arcsec² from atlas artificial brightness only (predicted SQM-L).
  static double artificialMcdToSqmMag(double artificialMcd) {
    return totalMcdToSqmMag(artificialMcd + sqmNaturalBackgroundMcd);
  }

  /// Artificial / natural ratio used in Falchi 2016 maps.
  static double artificialRatio(double artificialMcd) {
    if (artificialMcd <= 0) return 0;
    return artificialMcd / falchiNaturalReferenceMcd;
  }

  /// Falchi color bin index (1–14) from atlas artificial brightness.
  static int falchiColorBin(double artificialMcd) {
    final ratio = artificialRatio(artificialMcd);
    for (var i = 0; i < falchiRatioThresholds.length; i++) {
      if (ratio < falchiRatioThresholds[i]) {
        return i + 1;
      }
    }
    return falchiRatioThresholds.length + 1;
  }

  /// Bortle 4 sub-tier from Falchi bin (6–7 어두움, 8 보통, 9 밝음).
  static Bortle4SubTier? bortle4SubTier(double artificialMcd) {
    if (artificialMcdToBortle(artificialMcd) != 4) return null;

    final bin = falchiColorBin(artificialMcd);
    if (bin <= 7) return Bortle4SubTier.dark;
    if (bin == 8) return Bortle4SubTier.mid;
    return Bortle4SubTier.bright;
  }

  static String bortle4SubTierLabel(Bortle4SubTier tier) {
    switch (tier) {
      case Bortle4SubTier.dark:
        return '어두움';
      case Bortle4SubTier.mid:
        return '보통';
      case Bortle4SubTier.bright:
        return '밝음';
    }
  }

  /// UI headline including Bortle 4 sub-tier when applicable.
  static String bortleDisplayLabel(int bortle, {double? artificialMcd}) {
    final base = '${bortleShortLabel(bortle)} · ${bortleLabel(bortle)}';
    if (bortle == 4 && artificialMcd != null) {
      final tier = bortle4SubTier(artificialMcd);
      if (tier != null) {
        return '$base · ${bortle4SubTierLabel(tier)}';
      }
    }
    return base;
  }

  /// Bortle class (1–9) from atlas artificial brightness (mcd/m²).
  static int artificialMcdToBortle(double artificialMcd) {
    if (artificialMcd <= 0) return 1;

    final ratio = artificialRatio(artificialMcd);
    final bin = falchiColorBin(artificialMcd);
    final index = (bin - 1).clamp(0, falchiBinToBortle.length - 1);
    var bortle = falchiBinToBortle[index];

    // Floors apply only above Falchi bin 12 so bins 1–12 keep full gradation.
    if (ratio >= _urbanCoreRatio) return math.max(bortle, 9);
    if (ratio >= _brightCityRatio) return math.max(bortle, 8);

    return bortle;
  }

  /// Bortle from Falchi Table 1 bin index (1–14).
  static int bortleFromFalchiBin(int bin) {
    final index = (bin - 1).clamp(0, falchiBinToBortle.length - 1);
    return falchiBinToBortle[index];
  }

  /// Classic SQM limits (mag/arcsec², higher = darker sky).
  static int sqmMagToBortle(double sqmMag) {
    if (sqmMag >= 21.80) return 1;
    if (sqmMag >= 21.70) return 2;
    if (sqmMag >= 21.60) return 3;
    if (sqmMag >= 21.50) return 4;
    if (sqmMag >= 20.50) return 5;
    if (sqmMag >= 19.50) return 6;
    if (sqmMag >= 18.75) return 7;
    if (sqmMag >= 18.00) return 8;
    return 9;
  }

  static String bortleLabel(int bortle) {
    switch (bortle) {
      case 1:
        return '실질적 암야';
      case 2:
        return '탁월한 암야';
      case 3:
        return '시골 하늘';
      case 4:
        return '시골·교외';
      case 5:
        return '준교외';
      case 6:
        return '밝은 교외';
      case 7:
        return '교외·도시';
      case 8:
        return '밝은 도시';
      case 9:
        return '도시 중심';
      default:
        return '알 수 없음';
    }
  }

  static String bortleShortLabel(int bortle) => 'Bortle $bortle';

  static String sqmRangeLabel(int bortle) {
    switch (bortle) {
      case 1:
        return 'SQM ≥ 21.80';
      case 2:
        return 'SQM 21.70 ~ 21.80';
      case 3:
        return 'SQM 21.60 ~ 21.70';
      case 4:
        return 'SQM 21.50 ~ 21.60';
      case 5:
        return 'SQM 20.50 ~ 21.50';
      case 6:
        return 'SQM 19.50 ~ 20.50';
      case 7:
        return 'SQM 18.75 ~ 19.50';
      case 8:
        return 'SQM 18.00 ~ 18.75';
      case 9:
        return 'SQM < 18.00';
      default:
        return '';
    }
  }

  static String observationRating(int bortle) {
    if (bortle <= 2) return '★★★★★';
    if (bortle == 3) return '★★★★☆';
    if (bortle == 4) return '★★★★☆';
    if (bortle == 5) return '★★★☆☆';
    if (bortle == 6) return '★★☆☆☆';
    if (bortle == 7) return '★★☆☆☆';
    if (bortle == 8) return '★☆☆☆☆';
    return '관측 비추천';
  }
}

/// Bortle 4 brightness sub-tier (Falchi bin 6–9 within class 4).
enum Bortle4SubTier {
  dark,
  mid,
  bright,
}
