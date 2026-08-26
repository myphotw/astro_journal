import 'catalog_object.dart';
import 'observation_feasibility_result.dart';
import 'observation_status.dart';
import 'shooting_record.dart';
import 'site_horizon_profile.dart';
import 'weather_data.dart';
import 'weather_forecast_slot.dart';
import '../../services/observation_score_service.dart';
import '../../services/session_weather_index.dart';

/// Immutable snapshot of all observation inputs shared by recommendation
/// and scheduling engines.
class ObservationContext {
  const ObservationContext({
    required this.latitude,
    required this.longitude,
    this.brightness,
    this.bortle,
    required this.moonIllumination,
    required this.moonAltitude,
    required this.moonAzimuth,
    required this.cloudCover,
    required this.observationStart,
    required this.observationEnd,
    required this.currentTime,
    this.weather,
    this.forecasts = const [],
    this.sessionWeather,
    this.siteSlotScores = const {},
    this.siteSlotFeasibility = const {},
    this.observationWindow,
    this.observationStatus = ObservationStatus.good,
    this.statusPrimaryReason,
    this.statusUserMessage,
    this.catalog = const [],
    this.shootingRecords = const [],
    this.horizonProfile = const SiteHorizonProfile(),
  });

  final double latitude;
  final double longitude;
  final double? brightness;
  final int? bortle;
  final double moonIllumination;
  final double moonAltitude;
  final double moonAzimuth;
  final int cloudCover;
  final DateTime observationStart;
  final DateTime observationEnd;
  final DateTime currentTime;
  final WeatherData? weather;
  final List<WeatherForecastSlot> forecasts;
  final SessionWeatherIndex? sessionWeather;
  final Map<DateTime, double> siteSlotScores;
  final Map<DateTime, ObservationFeasibilityResult> siteSlotFeasibility;
  final ObservationWindow? observationWindow;
  final ObservationStatus observationStatus;
  final String? statusPrimaryReason;
  final String? statusUserMessage;
  final List<CatalogObject> catalog;
  final List<ShootingRecord> shootingRecords;
  final SiteHorizonProfile horizonProfile;

  ObservationContext copyWith({
    double? latitude,
    double? longitude,
    double? brightness,
    int? bortle,
    double? moonIllumination,
    double? moonAltitude,
    double? moonAzimuth,
    int? cloudCover,
    DateTime? observationStart,
    DateTime? observationEnd,
    DateTime? currentTime,
    WeatherData? weather,
    List<WeatherForecastSlot>? forecasts,
    SessionWeatherIndex? sessionWeather,
    Map<DateTime, double>? siteSlotScores,
    Map<DateTime, ObservationFeasibilityResult>? siteSlotFeasibility,
    ObservationWindow? observationWindow,
    ObservationStatus? observationStatus,
    String? statusPrimaryReason,
    String? statusUserMessage,
    List<CatalogObject>? catalog,
    List<ShootingRecord>? shootingRecords,
    SiteHorizonProfile? horizonProfile,
  }) {
    return ObservationContext(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      brightness: brightness ?? this.brightness,
      bortle: bortle ?? this.bortle,
      moonIllumination: moonIllumination ?? this.moonIllumination,
      moonAltitude: moonAltitude ?? this.moonAltitude,
      moonAzimuth: moonAzimuth ?? this.moonAzimuth,
      cloudCover: cloudCover ?? this.cloudCover,
      observationStart: observationStart ?? this.observationStart,
      observationEnd: observationEnd ?? this.observationEnd,
      currentTime: currentTime ?? this.currentTime,
      weather: weather ?? this.weather,
      forecasts: forecasts ?? this.forecasts,
      sessionWeather: sessionWeather ?? this.sessionWeather,
      siteSlotScores: siteSlotScores ?? this.siteSlotScores,
      siteSlotFeasibility: siteSlotFeasibility ?? this.siteSlotFeasibility,
      observationWindow: observationWindow ?? this.observationWindow,
      observationStatus: observationStatus ?? this.observationStatus,
      statusPrimaryReason: statusPrimaryReason ?? this.statusPrimaryReason,
      statusUserMessage: statusUserMessage ?? this.statusUserMessage,
      catalog: catalog ?? this.catalog,
      shootingRecords: shootingRecords ?? this.shootingRecords,
      horizonProfile: horizonProfile ?? this.horizonProfile,
    );
  }
}
