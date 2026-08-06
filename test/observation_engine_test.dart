import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/observation_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObservationEngine', () {
    test('buildContext computes moon and night window from weather', () async {
      final currentTime = DateTime(2026, 7, 1, 18, 0);
      final weather = WeatherData(
        temperature: 20,
        feelsLike: 20,
        humidity: 50,
        windSpeed: 2,
        windDegree: 180,
        pressure: 1013,
        cloudCoverage: 25,
        visibility: 10000,
        sunrise: DateTime(2026, 7, 2, 5, 30),
        sunset: DateTime(2026, 7, 1, 19, 45),
        description: 'clear',
        cityName: 'Seoul',
      );

      final moonInfo = ObservationScoreService.computeMoonInfo(currentTime);
      final moonCoords = CelestialPositionService().getMoonEquatorial(currentTime);
      final moonAltAz = CelestialPositionService.computeAltAz(
        raHours: moonCoords.raHours,
        decDeg: moonCoords.decDeg,
        latDeg: 37.5,
        lonDeg: 127.0,
        time: currentTime,
      );
      final nightWindow = ObservationScoreService.observationNightWindow(
        now: currentTime,
        sunrise: weather.sunrise,
        sunset: weather.sunset,
      );

      final context = ObservationContext(
        latitude: 37.5,
        longitude: 127.0,
        brightness: 0.5,
        bortle: 3,
        moonIllumination: moonInfo.illumination,
        moonAltitude: moonAltAz.altitude,
        moonAzimuth: moonAltAz.azimuth,
        cloudCover: weather.cloudCoverage,
        observationStart: nightWindow.nightStart,
        observationEnd: nightWindow.nightEnd,
        currentTime: currentTime,
        weather: weather,
      );

      expect(context.cloudCover, 25);
      expect(context.moonIllumination, greaterThanOrEqualTo(0));
      expect(context.moonIllumination, lessThanOrEqualTo(1));
      expect(context.observationStart.isBefore(context.observationEnd), isTrue);
      expect(context.copyWith(cloudCover: 10).cloudCover, 10);
    });
  });
}
