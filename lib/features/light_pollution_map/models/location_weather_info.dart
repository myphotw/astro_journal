import '../../../data/models/observation_context.dart';
import '../../../data/models/observation_status.dart';
import '../../../data/models/tonight_observation_session.dart';
import '../../../data/models/weather_data.dart';
import '../../../data/models/weather_forecast_slot.dart';
import '../../../services/observation_engine.dart';
import '../../../services/observation_score_service.dart';
import 'hourly_weather_slot.dart';
import 'shooting_status.dart';

/// Current and hourly weather snapshot for a map location popup.
class LocationWeatherInfo {
  const LocationWeatherInfo({
    required this.temperature,
    required this.starCount,
    required this.cloudCoverage,
    required this.precipitationProbability,
    required this.windSpeed,
    required this.observationScore,
    required this.observationStatus,
    required this.shootingStatus,
    this.statusMessage,
    this.hourlySlots = const [],
  });

  final double temperature;
  final int starCount;
  final int cloudCoverage;
  final double precipitationProbability;
  final double windSpeed;
  final int observationScore;
  final ObservationStatus observationStatus;
  final ShootingStatus shootingStatus;
  final String? statusMessage;
  final List<HourlyWeatherSlot> hourlySlots;

  bool get isObservationFeasible =>
      observationStatus != ObservationStatus.unavailable;

  String get starsText =>
      '${'★' * starCount}${'☆' * (5 - starCount)}';

  String? get statusPrimaryReason => statusMessage;

  String get statusEmoji {
    if (!isObservationFeasible) return '🔴';
    return switch (observationStatus) {
      ObservationStatus.good => '🟢',
      ObservationStatus.limited => '🟡',
      ObservationStatus.unavailable => '🔴',
    };
  }

  String get statusMessageText {
    if (!isObservationFeasible) {
      return statusMessage ??
          statusPrimaryReason ??
          observationStatus.headline;
    }

    return switch (observationStatus) {
      ObservationStatus.good => observationStatus.headline,
      ObservationStatus.limited => observationStatus.limitedRecommendationNotice,
      ObservationStatus.unavailable => observationStatus.headline,
    };
  }

  /// Main-screen aligned status line for the weather tab.
  String get statusDisplayText => '$statusEmoji $statusMessageText';

  static const maxHourlySlots = 8;

  /// Builds observation index using the same pipeline as the home screen.
  static Future<LocationWeatherInfo> buildWithEngine({
    required ObservationEngine observationEngine,
    required double latitude,
    required double longitude,
    required WeatherData current,
    required List<WeatherForecastSlot> forecasts,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final nightWindow = ObservationScoreService.observationNightWindow(
      now: time,
      sunrise: current.sunrise,
      sunset: current.sunset,
    );

    final context = await observationEngine.buildContext(
      latitude: latitude,
      longitude: longitude,
      currentTime: time,
      weather: current,
      forecasts: forecasts,
      session: TonightObservationSession(
        start: nightWindow.nightStart,
        end: nightWindow.nightEnd,
      ),
    );

    final summary = ObservationScoreService.buildTonightSummary(
      context: context,
      forecasts: forecasts,
      sunrise: current.sunrise,
      sunset: current.sunset,
      now: time,
    );

    return fromContext(
      context: context,
      summary: summary,
      current: current,
      now: time,
    );
  }

  static LocationWeatherInfo fromContext({
    required ObservationContext context,
    required TonightObservationSummary? summary,
    required WeatherData current,
    DateTime? now,
  }) {
    final status = context.observationStatus;
    final score = status == ObservationStatus.unavailable
        ? 0
        : (summary?.finalScore ?? 0);
    final starCount = status.homeStarCount;
    final statusMessage = context.statusUserMessage ?? context.statusPrimaryReason;

    final nearest = summary?.slots.isNotEmpty == true
        ? _nearestSlot(summary!.slots, now ?? DateTime.now())
        : null;

    return LocationWeatherInfo(
      temperature: current.temperature,
      starCount: starCount,
      cloudCoverage: summary?.averageCloudCoverage.round() ??
          current.cloudCoverage,
      precipitationProbability:
          summary?.averagePrecipitationPop ?? nearest?.forecast.pop ?? 0,
      windSpeed: summary?.averageWindSpeed ?? current.windSpeed,
      observationScore: score,
      observationStatus: status,
      shootingStatus: ShootingStatus.fromObservationStatus(status),
      statusMessage: statusMessage,
      hourlySlots: _buildHourlySlots(summary?.slots ?? const [], now),
    );
  }

  static TonightObservationSlot? _nearestSlot(
    List<TonightObservationSlot> slots,
    DateTime now,
  ) {
    TonightObservationSlot? nearest;
    var smallestDelta = Duration.zero;
    for (final slot in slots) {
      final delta = slot.targetTime.difference(now).abs();
      if (nearest == null || delta < smallestDelta) {
        nearest = slot;
        smallestDelta = delta;
      }
    }
    return nearest;
  }

  static List<HourlyWeatherSlot> _buildHourlySlots(
    List<TonightObservationSlot> slots,
    DateTime? now,
  ) {
    if (slots.isEmpty) return const [];

    final reference = now ?? DateTime.now();
    final upcoming = [...slots]
      ..sort((a, b) => a.targetTime.compareTo(b.targetTime));
    final filtered = upcoming
        .where((slot) => !slot.targetTime.isBefore(reference))
        .take(maxHourlySlots)
        .toList();

    return filtered.map(HourlyWeatherSlot.fromTonightSlot).toList();
  }
}
