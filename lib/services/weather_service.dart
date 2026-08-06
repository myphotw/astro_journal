import '../data/models/api_test_result.dart';
import '../data/models/weather_data.dart';
import '../data/models/weather_forecast_slot.dart';
import 'api_key_service.dart';
import 'app_logger.dart';
import 'base_api_service.dart';

/// Service for OpenWeatherMap (https://openweathermap.org/api).
///
/// All location queries use latitude/longitude rather than city names.
///
/// Planned endpoints (extend as needed):
/// - Current weather  GET /weather
/// - 3-hour Forecast  GET /forecast
/// - Hourly           GET /forecast/hourly  (One Call API)
/// - Daily            GET /forecast/daily   (One Call API)
class WeatherService extends BaseApiService {
  WeatherService(this._keyService)
      : super(baseUrl: 'https://api.openweathermap.org/data/2.5');

  final ApiKeyService _keyService;

  static const _tag = 'WeatherService';

  /// Fetches current weather at [lat], [lng].
  ///
  /// Throws [ApiException] if the API key is missing or the request fails.
  Future<WeatherData> getCurrentWeather(double lat, double lng) async {
    final apiKey = await _keyService.get(ApiKeyType.weather);
    if (apiKey == null || apiKey.isEmpty) {
      throw const ApiException('Weather API Key가 저장되어 있지 않습니다.');
    }

    final data = await get('/weather', queryParams: {
      'lat': lat.toStringAsFixed(6),
      'lon': lng.toStringAsFixed(6),
      'appid': apiKey,
      'units': 'metric',
      'lang': 'kr',
    });

    return WeatherData.fromJson(data);
  }

  /// Fetches 3-hour forecast at [lat], [lng] (up to ~5 days).
  Future<List<WeatherForecastSlot>> getForecast(double lat, double lng) async {
    final apiKey = await _keyService.get(ApiKeyType.weather);
    if (apiKey == null || apiKey.isEmpty) {
      throw const ApiException('Weather API Key가 저장되어 있지 않습니다.');
    }

    final data = await get('/forecast', queryParams: {
      'lat': lat.toStringAsFixed(6),
      'lon': lng.toStringAsFixed(6),
      'appid': apiKey,
      'units': 'metric',
      'lang': 'kr',
    });

    final list = data['list'] as List<dynamic>? ?? [];
    return list
        .map((item) => WeatherForecastSlot.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Tests connectivity by fetching weather at [lat], [lng] with the stored key.
  Future<ApiTestResult> testConnection(double lat, double lng) async {
    final apiKey = await _keyService.get(ApiKeyType.weather);
    if (apiKey == null || apiKey.isEmpty) {
      return ApiTestResult.failure(message: 'Weather API Key가 저장되어 있지 않습니다.');
    }

    try {
      final raw = await getRaw('/weather', queryParams: {
        'lat': lat.toStringAsFixed(6),
        'lon': lng.toStringAsFixed(6),
        'appid': apiKey,
        'units': 'metric',
        'lang': 'kr',
      });
      AppLogger.info(_tag, 'Test OK (${raw.elapsedMs}ms)');
      return ApiTestResult.success(
        statusCode: raw.statusCode,
        responseTimeMs: raw.elapsedMs,
        data: raw.data,
      );
    } on ApiException catch (e) {
      AppLogger.error(_tag, e);
      return ApiTestResult.failure(
        message: e.message,
        statusCode: e.statusCode,
      );
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return ApiTestResult.failure(message: e.toString());
    }
  }
}
