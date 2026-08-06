import 'package:astro_journal/data/models/observation_site_favorite.dart';
import 'package:astro_journal/data/models/observation_status.dart';
import 'package:astro_journal/features/light_pollution_map/models/favorite_location_summary.dart';
import 'package:astro_journal/features/light_pollution_map/models/location_weather_info.dart';
import 'package:astro_journal/features/light_pollution_map/models/shooting_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FavoriteLocationSummary', () {
    final favorite = ObservationSiteFavorite(
      id: 'fav-1',
      name: '지리산 정령치',
      latitude: 35.336,
      longitude: 127.730,
      bortle: 2,
      createdAt: DateTime(2026, 7, 7),
    );

    test('formats labels for dropdown item', () {
      final summary = FavoriteLocationSummary(
        favorite: favorite,
        weatherInfo: const LocationWeatherInfo(
          temperature: 12,
          starCount: 4,
          cloudCoverage: 15,
          precipitationProbability: 10,
          windSpeed: 2.5,
          observationScore: 82,
          observationStatus: ObservationStatus.good,
          shootingStatus: ShootingStatus.good,
        ),
        recommendedEquipmentName: 'S30 Pro',
        recommendedTargetNames: const ['M31', 'M42', 'M45'],
      );

      expect(summary.bortleLabel, 'Bortle 2');
      expect(summary.starsText, '★★★★☆');
      expect(summary.cloudCoverage, 15);
      expect(summary.equipmentLabel, 'S30 Pro');
      expect(summary.targetsLabel, 'M31, M42, M45');
    });

    test('uses fallback labels when data is missing', () {
      final summary = FavoriteLocationSummary(
        favorite: ObservationSiteFavorite(
          id: 'fav-2',
          name: '집',
          latitude: 37.5,
          longitude: 127.0,
          createdAt: DateTime(2026, 7, 7),
        ),
      );

      expect(summary.bortleLabel, 'Bortle -');
      expect(summary.starsText, '☆☆☆☆☆');
      expect(summary.equipmentLabel, '-');
      expect(summary.targetsLabel, '-');
    });
  });
}
