/// Catalog detail suitability for the administrator reference Bortle site.
enum CatalogExposureFeasibility {
  recommended,
  feasible,
  notRecommended,
  stronglyNotRecommended,
}

extension CatalogExposureFeasibilityLabels on CatalogExposureFeasibility {
  String get statusLabel => switch (this) {
        CatalogExposureFeasibility.recommended => '추천',
        CatalogExposureFeasibility.feasible => '촬영 가능',
        CatalogExposureFeasibility.notRecommended => '비추천',
        CatalogExposureFeasibility.stronglyNotRecommended => '매우 비추천',
      };

  bool get showsCurrentExposureTime =>
      this == CatalogExposureFeasibility.recommended ||
      this == CatalogExposureFeasibility.feasible;

  bool get showsIdealEnvironment =>
      this == CatalogExposureFeasibility.notRecommended ||
      this == CatalogExposureFeasibility.stronglyNotRecommended;
}

/// Exposure guidance for catalog detail (reference Bortle only).
class CatalogExposureGuidance {
  const CatalogExposureGuidance({
    required this.referenceBortle,
    required this.feasibility,
    this.currentMinimumMinutes,
    this.currentRecommendedMinutes,
    this.reason,
    this.idealBortle,
    this.idealMinimumMinutes,
    this.idealRecommendedMinutes,
  });

  final int referenceBortle;
  final CatalogExposureFeasibility feasibility;
  final int? currentMinimumMinutes;
  final int? currentRecommendedMinutes;

  /// Single short reason when [feasibility] is not recommended.
  final String? reason;

  final int? idealBortle;
  final int? idealMinimumMinutes;
  final int? idealRecommendedMinutes;

  String get currentEnvironmentLabel => '현재 환경 (Bortle $referenceBortle)';

  String? get currentExposureLine {
    if (!feasibility.showsCurrentExposureTime) return null;
    final min = currentMinimumMinutes;
    final rec = currentRecommendedMinutes;
    if (min == null || rec == null) return null;
    return '$min분 / $rec분';
  }

  String? get idealEnvironmentLabel {
    final bortle = idealBortle;
    if (bortle == null) return null;
    return 'Bortle $bortle 이하';
  }

  String? get idealExposureLine {
    final min = idealMinimumMinutes;
    final rec = idealRecommendedMinutes;
    if (min == null || rec == null) return null;
    return '$min분 / $rec분';
  }
}
