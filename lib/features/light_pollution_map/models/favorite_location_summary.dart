import '../../../data/models/observation_site_favorite.dart';
import 'location_weather_info.dart';

class FavoriteLocationSummary {
  const FavoriteLocationSummary({
    required this.favorite,
    this.weatherInfo,
    this.isLoading = false,
    this.recommendedEquipmentName,
    this.recommendedTargetNames = const [],
  });

  final ObservationSiteFavorite favorite;
  final LocationWeatherInfo? weatherInfo;
  final bool isLoading;
  final String? recommendedEquipmentName;
  final List<String> recommendedTargetNames;

  String get starsText => weatherInfo?.starsText ?? '☆☆☆☆☆';

  int get cloudCoverage => weatherInfo?.cloudCoverage ?? 0;

  String get bortleLabel {
    final bortle = favorite.bortle;
    if (bortle == null) return 'Bortle -';
    return 'Bortle $bortle';
  }

  String get targetsLabel {
    if (recommendedTargetNames.isEmpty) return '-';
    return recommendedTargetNames.join(', ');
  }

  String get equipmentLabel => recommendedEquipmentName ?? '-';
}
