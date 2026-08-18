import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';

/// Persists the last successful weather API response for offline display.
class WeatherCacheService {
  static const _cacheKey = 'weather_cache_v1';
  static const maxAge = Duration(hours: 12);

  Future<void> save({
    required double latitude,
    required double longitude,
    required WeatherData weather,
    required List<WeatherForecastSlot> forecasts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'latitude': latitude,
      'longitude': longitude,
      'cachedAt': DateTime.now().toIso8601String(),
      'weather': weather.toJson(),
      'forecasts': forecasts.map((slot) => slot.toJson()).toList(),
    };
    await prefs.setString(_cacheKey, jsonEncode(payload));
  }

  Future<WeatherCacheEntry?> load({double? latitude, double? longitude}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(map['cachedAt'] as String);
      if (DateTime.now().difference(cachedAt) > maxAge) return null;

      final cachedLat = (map['latitude'] as num).toDouble();
      final cachedLng = (map['longitude'] as num).toDouble();

      if (latitude != null && longitude != null) {
        if ((latitude - cachedLat).abs() > 0.5 ||
            (longitude - cachedLng).abs() > 0.5) {
          return null;
        }
      }

      final forecastsRaw = map['forecasts'] as List<dynamic>? ?? [];
      return WeatherCacheEntry(
        latitude: cachedLat,
        longitude: cachedLng,
        cachedAt: cachedAt,
        weather: WeatherData.fromCacheJson(
          map['weather'] as Map<String, dynamic>,
        ),
        forecasts: forecastsRaw
            .map(
              (item) => WeatherForecastSlot.fromCacheJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}

class WeatherCacheEntry {
  const WeatherCacheEntry({
    required this.latitude,
    required this.longitude,
    required this.cachedAt,
    required this.weather,
    required this.forecasts,
  });

  final double latitude;
  final double longitude;
  final DateTime cachedAt;
  final WeatherData weather;
  final List<WeatherForecastSlot> forecasts;
}
