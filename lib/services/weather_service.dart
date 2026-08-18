import '../data/models/api_test_result.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import 'api_key_service.dart';
import 'app_logger.dart';
import 'base_api_service.dart';
import 'tc_backend_external_api_client.dart';
import 'tc_backend_settings_service.dart';

/// Weather facade backed by TC-Backend's normalized OpenWeatherMap adapter.
///
/// [legacyKeyService] remains only for constructor compatibility with V1.
/// Provider API keys are never read or sent by production weather requests.
class WeatherService {
  WeatherService(
    ApiKeyService legacyKeyService, {
    TcBackendExternalApiClient? backendClient,
  }) : _backend =
           backendClient ??
           TcBackendExternalApiClient(
             settingsService: TcBackendSettingsService(),
           );

  final TcBackendExternalApiClient _backend;
  static const _tag = 'WeatherService';

  Future<WeatherData> getCurrentWeather(double lat, double lng) async {
    try {
      final json = await _backend.getMap(
        '/api/common/weather/current',
        query: {
          'lat': lat.toStringAsFixed(6),
          'lon': lng.toStringAsFixed(6),
          'language': 'ko',
        },
      );
      return _current(json);
    } on TcBackendExternalApiException catch (error) {
      throw ApiException(error.message, statusCode: error.statusCode);
    }
  }

  Future<List<WeatherForecastSlot>> getForecast(double lat, double lng) async {
    try {
      final json = await _backend.getMap(
        '/api/common/weather/forecast',
        query: {
          'lat': lat.toStringAsFixed(6),
          'lon': lng.toStringAsFixed(6),
          'language': 'ko',
        },
      );
      final raw = json['items'];
      if (raw is! List) {
        throw const TcBackendExternalApiException(
          code: TcBackendExternalApiErrorCode.malformedResponse,
          message: '날씨 예보 응답에 items가 없습니다.',
        );
      }
      return raw
          .whereType<Map>()
          .map((item) => _forecast(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on TcBackendExternalApiException catch (error) {
      throw ApiException(error.message, statusCode: error.statusCode);
    }
  }

  Future<ApiTestResult> testConnection(double lat, double lng) async {
    final stopwatch = Stopwatch()..start();
    try {
      final weather = await getCurrentWeather(lat, lng);
      stopwatch.stop();
      return ApiTestResult.success(
        statusCode: 200,
        responseTimeMs: stopwatch.elapsedMilliseconds,
        data: weather.toJson(),
      );
    } on ApiException catch (error) {
      AppLogger.error(_tag, error);
      return ApiTestResult.failure(
        message: error.message,
        statusCode: error.statusCode,
      );
    } catch (error, stackTrace) {
      AppLogger.error(_tag, error, stackTrace);
      return ApiTestResult.failure(message: error.toString());
    }
  }

  WeatherData _current(Map<String, dynamic> json) => WeatherData(
    temperature: _double(json['temperature']),
    feelsLike: _double(json['feels_like']),
    humidity: _int(json['humidity']),
    windSpeed: _double(json['wind_speed']),
    windDegree: _int(json['wind_direction']),
    pressure: _int(json['pressure']),
    cloudCoverage: _int(json['clouds']),
    visibility: _int(json['visibility']),
    sunrise: _dateTime(json['sunrise']),
    sunset: _dateTime(json['sunset']),
    description: _string(json['description']),
    cityName: _string(json['city_name']),
  );

  WeatherForecastSlot _forecast(Map<String, dynamic> json) {
    final probability = _double(json['precipitation_probability']);
    return WeatherForecastSlot(
      time: _dateTime(json['timestamp']).toLocal(),
      temperature: _double(json['temperature']),
      humidity: _int(json['humidity']),
      windSpeed: _double(json['wind_speed']),
      cloudCoverage: _int(json['clouds']),
      visibility: json['visibility'] == null ? 10000 : _int(json['visibility']),
      pop: probability <= 1 ? probability * 100 : probability,
      description: _string(json['description']),
      icon: _string(json['icon']),
      rainVolumeMm: json['rain_volume_mm'] == null
          ? null
          : _double(json['rain_volume_mm']),
    );
  }

  double _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  String _string(Object? value) => value?.toString() ?? '';

  DateTime _dateTime(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
