import '../core/constants/observation_quality_weights.dart';
import '../data/models/observation_feasibility_reason.dart';
import '../data/models/observation_feasibility_result.dart';
import '../data/models/observation_quality_component.dart';
import '../data/models/observation_quality_index.dart';
import '../data/models/weather_forecast_slot.dart';
import 'observation_feasibility_policy.dart';
import 'observation_score_service.dart';

/// Single source of truth for Observation Quality Index (OQI).
class ObservationQualityService {
  const ObservationQualityService();

  static const cloudCategory = '구름';
  static const rainCategory = '강수';
  static const visibilityCategory = '가시거리';
  static const moonCategory = '달 영향';
  static const windCategory = '풍속';
  static const condensationCategory = '결로';

  ObservationQualityIndex computeSlotQuality({
    required WeatherForecastSlot forecast,
    required MoonPhaseInfo moon,
    ObservationFeasibilityResult? feasibility,
    double? moonSeparationDeg,
  }) {
    if (feasibility != null && !feasibility.canObserve) {
      return ObservationQualityIndex.infeasible(
        primaryInfeasibleReason: feasibility.reason,
        userMessage: formatInfeasibleMessage(feasibility),
      );
    }

    final components = _buildComponents(
      forecast: forecast,
      moon: moon,
      moonSeparationDeg: moonSeparationDeg,
    );
    final weighted = _weightedAverage(components);
    final cloudQuality =
        components.firstWhere((c) => c.category == cloudCategory).quality;
    final oqi = (weighted * cloudQuality / 100.0).clamp(0.0, 100.0);

    return ObservationQualityIndex(
      oqi: oqi,
      components: components,
    );
  }

  ObservationQualityIndex computeFromForecast({
    required WeatherForecastSlot forecast,
    required MoonPhaseInfo moon,
    ObservationFeasibilityPolicy? feasibilityPolicy,
    double? moonSeparationDeg,
  }) {
    final policy = feasibilityPolicy ?? const ObservationFeasibilityPolicy();
    final feasibility = policy.evaluateSiteSlot(forecast: forecast);
    return computeSlotQuality(
      forecast: forecast,
      moon: moon,
      feasibility: feasibility,
      moonSeparationDeg: moonSeparationDeg,
    );
  }

  ObservationQualityIndex averageQuality(
    Iterable<ObservationQualityIndex> indices,
  ) {
    final observable =
        indices.where((index) => index.isObservable && index.oqi != null).toList();
    if (observable.isEmpty) {
      final infeasible = indices.where((index) => !index.isObservable);
      final primary = ObservationFeasibilityPolicy.aggregatePrimaryReason(
        results: infeasible
            .map(
              (index) => ObservationFeasibilityResult.infeasible(
                reason: index.primaryInfeasibleReason ?? '',
                failedConditions: const [],
              ),
            )
            .where((result) => result.reason?.isNotEmpty ?? false),
      );
      return ObservationQualityIndex.infeasible(
        primaryInfeasibleReason: primary,
        userMessage: formatInfeasibleMessageFromReason(primary),
      );
    }

    final categories = [
      cloudCategory,
      rainCategory,
      visibilityCategory,
      moonCategory,
      windCategory,
      condensationCategory,
    ];

    final averagedComponents = categories.map((category) {
      final values = observable
          .map((index) => index.componentFor(category)?.quality)
          .whereType<double>();
      final average = values.isEmpty
          ? 0.0
          : values.reduce((a, b) => a + b) / values.length;
      return ObservationQualityComponent(
        category: category,
        quality: average,
      );
    }).toList();

    final cloudAverage = averagedComponents
            .firstWhere((c) => c.category == cloudCategory)
            .quality /
        100.0;

    return ObservationQualityIndex(
      oqi: (_weightedAverage(averagedComponents) * cloudAverage)
          .clamp(0.0, 100.0),
      components: averagedComponents,
    );
  }

  List<ObservationQualityComponent> _buildComponents({
    required WeatherForecastSlot forecast,
    required MoonPhaseInfo moon,
    double? moonSeparationDeg,
  }) {
    return [
      ObservationQualityComponent(
        category: cloudCategory,
        quality: cloudQuality(forecast.cloudCoverage.toDouble()),
      ),
      ObservationQualityComponent(
        category: rainCategory,
        quality: rainQuality(forecast.pop),
      ),
      ObservationQualityComponent(
        category: visibilityCategory,
        quality: visibilityQuality(forecast.visibility),
      ),
      ObservationQualityComponent(
        category: moonCategory,
        quality: moonQuality(
          moonIllumination: moon.illumination,
          moonSeparationDeg: moonSeparationDeg,
        ),
      ),
      ObservationQualityComponent(
        category: windCategory,
        quality: windQuality(forecast.windSpeed),
      ),
      ObservationQualityComponent(
        category: condensationCategory,
        quality: condensationQuality(
          temperature: forecast.temperature,
          humidity: forecast.humidity,
        ),
      ),
    ];
  }

  static double cloudQuality(double cloudCoverage) {
    return _stepDownQuality(
      cloudCoverage.clamp(0, 100),
      const [
        (0, 100),
        (10, 95),
        (20, 90),
        (30, 80),
        (40, 65),
        (50, 45),
        (60, 25),
        (70, 10),
        (80, 0),
        (100, 0),
      ],
    );
  }

  static double rainQuality(double popPercent) {
    return _stepDownQuality(
      popPercent.clamp(0, 100),
      const [
        (0, 100),
        (10, 90),
        (20, 70),
        (40, 40),
        (60, 10),
        (80, 0),
        (100, 0),
      ],
    );
  }

  static double visibilityQuality(int visibilityMeters) {
    final km = visibilityMeters / 1000.0;
    return _stepDownQuality(
      km,
      const [
        (0, 0),
        (1, 0),
        (3, 30),
        (5, 60),
        (8, 80),
        (10, 90),
        (15, 100),
        (100, 100),
      ],
      ascending: true,
    );
  }

  static double windQuality(double windSpeed) {
    return _stepDownQuality(
      windSpeed.clamp(0, 100),
      const [
        (0, 100),
        (2, 100),
        (3, 90),
        (5, 75),
        (8, 50),
        (10, 30),
        (15, 0),
        (100, 0),
      ],
    );
  }

  static double condensationQuality({
    required double temperature,
    required int humidity,
  }) {
    final spread = temperature -
        ObservationScoreService.dewPointCelsius(temperature, humidity);
    return _stepDownQuality(
      spread,
      const [
        (0, 0),
        (1, 0),
        (2, 30),
        (3, 60),
        (5, 80),
        (7, 100),
        (20, 100),
      ],
      ascending: true,
    );
  }

  static double moonQuality({
    required double moonIllumination,
    double? moonSeparationDeg,
  }) {
    final illumBonus =
        (1 - moonIllumination.clamp(0.0, 1.0)) * (moonSeparationDeg == null ? 100 : 50);
    if (moonSeparationDeg == null) {
      return illumBonus.clamp(0.0, 100.0);
    }

    final separationBonus =
        (moonSeparationDeg.clamp(0.0, 120.0) / 120.0 * 50.0);
    return (illumBonus + separationBonus).clamp(0.0, 100.0);
  }

  static double _weightedAverage(List<ObservationQualityComponent> components) {
    final byCategory = {
      for (final component in components) component.category: component.quality,
    };

    final weighted = (byCategory[cloudCategory] ?? 0) *
            ObservationQualityWeights.cloud +
        (byCategory[rainCategory] ?? 0) * ObservationQualityWeights.rain +
        (byCategory[visibilityCategory] ?? 0) *
            ObservationQualityWeights.visibility +
        (byCategory[moonCategory] ?? 0) * ObservationQualityWeights.moon +
        (byCategory[windCategory] ?? 0) * ObservationQualityWeights.wind +
        (byCategory[condensationCategory] ?? 0) *
            ObservationQualityWeights.condensation;

    return weighted.clamp(0.0, 100.0);
  }

  static double _stepDownQuality(
    double value,
    List<(double threshold, double quality)> points, {
    bool ascending = false,
  }) {
    if (points.isEmpty) return 0;

    if (ascending) {
      for (var i = points.length - 1; i >= 0; i--) {
        if (value >= points[i].$1) {
          if (i == points.length - 1) return points[i].$2;
          final next = points[i + 1];
          final current = points[i];
          final span = next.$1 - current.$1;
          if (span <= 0) return next.$2;
          final t = ((value - current.$1) / span).clamp(0.0, 1.0);
          return current.$2 + (next.$2 - current.$2) * t;
        }
      }
      return points.first.$2;
    }

    for (var i = 0; i < points.length; i++) {
      if (value <= points[i].$1) {
        if (i == 0) return points[i].$2;
        final previous = points[i - 1];
        final current = points[i];
        final span = current.$1 - previous.$1;
        if (span <= 0) return current.$2;
        final t = ((value - previous.$1) / span).clamp(0.0, 1.0);
        return previous.$2 + (current.$2 - previous.$2) * t;
      }
    }
    return points.last.$2;
  }

  static String formatInfeasibleMessage(ObservationFeasibilityResult feasibility) {
    return formatInfeasibleMessageFromReason(feasibility.reason);
  }

  static String formatInfeasibleMessageFromReason(String? reason) {
    if (reason == null || reason.isEmpty) {
      return '오늘 밤은 관측이 어렵습니다.';
    }
    if (reason.contains('구름')) {
      return '오늘 밤은 구름이 많아 관측이 어렵습니다.';
    }
    if (reason.contains('강수')) {
      return '오늘 밤은 강수 가능성으로 관측이 어렵습니다.';
    }
    if (reason.contains('가시거리')) {
      return '오늘 밤은 가시거리 부족으로 관측이 어렵습니다.';
    }
    if (reason.contains('풍속')) {
      return '오늘 밤은 바람이 강해 관측이 어렵습니다.';
    }
    return '오늘 밤은 $reason';
  }

  static String? primaryReasonFromFeasibility(
    Iterable<ObservationFeasibilityResult> results,
    WeatherForecastSlot? sampleForecast,
  ) {
    return ObservationFeasibilityPolicy.aggregatePrimaryReason(
      results: results,
      sampleForecast: sampleForecast,
    );
  }

  static String userMessageForFeasibilityReason(
    ObservationFeasibilityReason reason,
  ) {
    return switch (reason) {
      ObservationFeasibilityReason.cloudTooHigh =>
        '오늘 밤은 구름이 많아 관측이 어렵습니다.',
      ObservationFeasibilityReason.rainProbability =>
        '오늘 밤은 강수 가능성으로 관측이 어렵습니다.',
      ObservationFeasibilityReason.visibilityTooLow =>
        '오늘 밤은 가시거리 부족으로 관측이 어렵습니다.',
      ObservationFeasibilityReason.windTooStrong =>
        '오늘 밤은 바람이 강해 관측이 어렵습니다.',
      _ => '오늘 밤은 관측이 어렵습니다.',
    };
  }
}
