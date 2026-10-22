import 'dart:async';

import 'package:astro_journal/data/models/observation_condition.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/weather_data.dart';
import 'package:astro_journal/data/models/weather_forecast_slot.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart';
import 'package:astro_journal/features/light_pollution_map/widgets/light_pollution_favorites_dropdown.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/geocoding_service.dart';
import 'package:astro_journal/services/light_pollution_tile_preload_service.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:astro_journal/services/observation_engine.dart';
import 'package:astro_journal/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _SiteRepository implements ObservationSiteRepository {
  _SiteRepository(this.sites);

  final List<ObservationSite> sites;

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      List<ObservationSite>.of(sites);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConditionService implements ObservationConditionService {
  @override
  Future<ObservationCondition> getConditionAt(
    double latitude,
    double longitude,
  ) async => ObservationCondition(
    latitude: latitude,
    longitude: longitude,
    brightness: 1.5,
    bortle: 5,
    sqm: 20.5,
    createdAt: DateTime(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedTilePreloadService implements LightPollutionTilePreloadService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WeatherService implements WeatherService {
  int currentCalls = 0;
  int forecastCalls = 0;
  final Map<double, Completer<WeatherData>> currentRequests = {};
  final Map<double, Completer<List<WeatherForecastSlot>>> forecastRequests = {};

  @override
  Future<WeatherData> getCurrentWeather(double lat, double lng) {
    currentCalls++;
    return currentRequests.putIfAbsent(lat, Completer<WeatherData>.new).future;
  }

  @override
  Future<List<WeatherForecastSlot>> getForecast(double lat, double lng) {
    forecastCalls++;
    return forecastRequests
        .putIfAbsent(lat, Completer<List<WeatherForecastSlot>>.new)
        .future;
  }

  void complete(double latitude, double temperature) {
    final now = DateTime.now();
    currentRequests[latitude]!.complete(
      WeatherData(
        temperature: temperature,
        feelsLike: temperature,
        humidity: 50,
        windSpeed: 1,
        windDegree: 0,
        pressure: 1010,
        cloudCoverage: 10,
        visibility: 10000,
        sunrise: DateTime(now.year, now.month, now.day, 6),
        sunset: DateTime(now.year, now.month, now.day, 18),
        description: 'clear',
        cityName: 'test',
      ),
    );
    forecastRequests[latitude]!.complete(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LightPollutionMapViewModel _viewModel({
  required _SiteRepository sites,
  required _WeatherService weather,
}) {
  final condition = _ConditionService();
  return LightPollutionMapViewModel(
    condition,
    GeocodingService(),
    _UnusedTilePreloadService(),
    weather,
    sites,
    ObservationEngine(condition, CelestialPositionService()),
  );
}

ObservationSite _site({
  required String id,
  required String name,
  required double latitude,
  int? bortle,
}) => ObservationSite(
  id: id,
  name: name,
  latitude: latitude,
  longitude: 127,
  bortle: bortle,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test(
    'opening saved sites uses local data without weather requests',
    () async {
      final weather = _WeatherService();
      final viewModel = _viewModel(
        sites: _SiteRepository([
          _site(id: 'home', name: '집', latitude: 37.5, bortle: 6),
        ]),
        weather: weather,
      );

      await viewModel.loadFavorites();
      viewModel.toggleFavoritesDropdown();

      expect(viewModel.isFavoritesDropdownOpen, isTrue);
      expect(viewModel.favorites.single.name, '집');
      expect(weather.currentCalls, 0);
      expect(weather.forecastCalls, 0);
    },
  );

  testWidgets('saved sites show only name and stored Bortle value', (
    tester,
  ) async {
    final weather = _WeatherService();
    final viewModel = _viewModel(
      sites: _SiteRepository([
        _site(id: 'home', name: '집', latitude: 37.5, bortle: 6),
        _site(id: 'unknown', name: '미확인 관측지', latitude: 35),
      ]),
      weather: weather,
    );
    await viewModel.loadFavorites();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: LightPollutionFavoritesDropdown(
              viewModel: viewModel,
              onSelect: (_) {},
              onUnfavorite: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('집'), findsOneWidget);
    expect(find.text('Bortle 6'), findsOneWidget);
    expect(find.text('미확인 관측지'), findsOneWidget);
    expect(find.text('Bortle -'), findsOneWidget);
    expect(find.textContaining('추천장비'), findsNothing);
    expect(find.textContaining('추천대상'), findsNothing);
  });

  test(
    'late weather result cannot overwrite the latest selected site',
    () async {
      final weather = _WeatherService();
      final viewModel = _viewModel(
        sites: _SiteRepository(const []),
        weather: weather,
      );

      await viewModel.selectLocation(
        const LatLng(35, 127),
        addressLabel: '첫 번째',
      );
      await viewModel.selectLocation(
        const LatLng(36, 127),
        addressLabel: '두 번째',
      );

      weather.complete(36, 22);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.selectedWeatherInfo?.temperature, 22);

      weather.complete(35, 11);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.selectedPosition, const LatLng(36, 127));
      expect(viewModel.selectedWeatherInfo?.temperature, 22);
    },
  );
}
