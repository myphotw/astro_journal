import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/api_test_result.dart';
import '../../../data/models/weather_data.dart';
import '../../../services/api_key_service.dart';
import '../../../services/astronomy_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/location_service.dart';
import '../../../services/weather_service.dart';

/// ViewModel for the API test screen.
///
/// Each test runs independently and updates its own state slice.
class ApiTestViewModel extends ChangeNotifier {
  ApiTestViewModel(
    this._locationService,
    this._astronomyService,
    this._weatherService,
    this._keyService,
    this._geocodingService,
  );

  final LocationService _locationService;
  final AstronomyService _astronomyService;
  final WeatherService _weatherService;
  final ApiKeyService _keyService;
  final GeocodingService _geocodingService;

  // ── GPS ────────────────────────────────────────────────────────────────────

  bool gpsLoading = false;
  LocationPermissionStatus? gpsPermission;
  bool? gpsServiceEnabled;
  LocationData? gpsLocation;
  String? gpsError;

  // ── Astronomy ──────────────────────────────────────────────────────────────

  bool astronomyLoading = false;
  ApiTestResult? astronomyResult;

  // ── Weather ────────────────────────────────────────────────────────────────

  bool weatherLoading = false;
  ApiTestResult? weatherResult;
  WeatherData? weatherData;

  // ── Map API ────────────────────────────────────────────────────────────────

  bool mapLoading = false;
  ApiTestResult? mapResult;
  GeocodingResult? mapGeoResult;
  LocationData? mapGpsLocation;
  bool? hasGoogleMapsKey;

  // ── Secure Storage ─────────────────────────────────────────────────────────

  bool storageLoading = false;
  String? maskedAstronomyId;
  bool? hasAstronomySecret;
  bool? hasWeatherKey;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> testGps() async {
    gpsLoading = true;
    gpsError = null;
    gpsLocation = null;
    notifyListeners();

    try {
      gpsServiceEnabled = await _locationService.isServiceEnabled();
      gpsPermission = await _locationService.requestPermission();
      gpsLocation = await _locationService.getCurrentLocation();
    } catch (e) {
      gpsError = e.toString().replaceFirst('Exception: ', '');
      gpsPermission ??= await _locationService.checkPermission();
      gpsServiceEnabled ??= await _locationService.isServiceEnabled();
    } finally {
      gpsLoading = false;
      notifyListeners();
    }
  }

  Future<void> testAstronomy() async {
    astronomyLoading = true;
    astronomyResult = null;
    notifyListeners();

    astronomyResult = await _astronomyService.testConnection();
    astronomyLoading = false;
    notifyListeners();
  }

  Future<void> testWeather() async {
    weatherLoading = true;
    weatherResult = null;
    weatherData = null;
    notifyListeners();

    // Acquire GPS first (reuse existing location if already fetched).
    LocationData? location = gpsLocation;
    if (location == null) {
      try {
        location = await _locationService.getCurrentLocation();
        gpsLocation = location;
        gpsPermission = LocationPermissionStatus.granted;
      } catch (e) {
        weatherResult = ApiTestResult.failure(
          message: 'GPS 위치를 가져올 수 없습니다: ${e.toString().replaceFirst("Exception: ", "")}',
        );
        weatherLoading = false;
        notifyListeners();
        return;
      }
    }

    weatherResult = await _weatherService.testConnection(
      location.latitude,
      location.longitude,
    );

    if (weatherResult!.success && weatherResult!.data != null) {
      try {
        weatherData = WeatherData.fromJson(weatherResult!.data!);
      } catch (_) {
        // Parse failure is non-fatal; result stays success.
      }
    }

    weatherLoading = false;
    notifyListeners();
  }

  /// Map API 테스트: API Key 확인 → GPS → Reverse Geocoding → 지도 표시 가능 여부.
  Future<void> testMap() async {
    mapLoading = true;
    mapResult = null;
    mapGeoResult = null;
    mapGpsLocation = null;
    hasGoogleMapsKey = null;
    notifyListeners();

    try {
      // 1. API 키 확인
      final mapsKey = await _keyService.get(ApiKeyType.googleMaps) ?? '';
      hasGoogleMapsKey = mapsKey.isNotEmpty;

      if (!hasGoogleMapsKey!) {
        mapResult = ApiTestResult.failure(
          message: 'Google Maps API Key가 설정되지 않았습니다.\nSettings에서 API 키를 입력해 주세요.',
        );
        mapLoading = false;
        notifyListeners();
        return;
      }

      // 2. GPS 위치 확인
      LocationData? location = gpsLocation;
      if (location == null) {
        try {
          location = await _locationService.getCurrentLocation();
          gpsLocation = location;
        } catch (e) {
          mapResult = ApiTestResult.failure(
            message: 'GPS 위치를 가져올 수 없습니다: ${e.toString().replaceFirst("Exception: ", "")}',
          );
          mapLoading = false;
          notifyListeners();
          return;
        }
      }
      mapGpsLocation = location;

      // 3. Reverse Geocoding 테스트
      final sw = Stopwatch()..start();
      final geoResult = await _geocodingService.getLocationInfo(
        location.latitude,
        location.longitude,
        mapsKey,
      );
      sw.stop();

      if (geoResult == null) {
        mapResult = ApiTestResult.failure(
          message: 'Reverse Geocoding 실패\n'
              '좌표: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}\n'
              'API 키가 유효한지 확인하세요.',
          responseTimeMs: sw.elapsedMilliseconds,
        );
      } else {
        mapGeoResult = geoResult;
        mapResult = ApiTestResult.success(
          statusCode: 200,
          responseTimeMs: sw.elapsedMilliseconds,
          data: {
            'locationName': geoResult.locationName,
            'address': geoResult.address,
            'lat': location.latitude,
            'lng': location.longitude,
          },
          message: 'API 인증 성공',
        );
      }
    } catch (e) {
      mapResult = ApiTestResult.failure(
        message: 'Map API 테스트 오류: $e',
      );
    } finally {
      mapLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkStorage() async {
    storageLoading = true;
    notifyListeners();

    try {
      final rawId = await _keyService.get(ApiKeyType.astronomyAppId);
      if (rawId != null && rawId.isNotEmpty) {
        maskedAstronomyId = rawId.length <= 8
            ? '••••••••'
            : '${rawId.substring(0, 4)}${'•' * (rawId.length - 8)}${rawId.substring(rawId.length - 4)}';
      } else {
        maskedAstronomyId = null;
      }

      hasAstronomySecret = await _keyService.has(ApiKeyType.astronomyAppSecret);
      hasWeatherKey = await _keyService.has(ApiKeyType.weather);
      final mapsKey = await _keyService.get(ApiKeyType.googleMaps) ?? '';
      hasGoogleMapsKey = mapsKey.isNotEmpty;
    } finally {
      storageLoading = false;
      notifyListeners();
    }
  }

  /// Compact JSON preview (max 800 chars) for display.
  String? jsonPreview(Map<String, dynamic>? data) {
    if (data == null) return null;
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    return encoded.length > 800 ? '${encoded.substring(0, 800)}…' : encoded;
  }
}
