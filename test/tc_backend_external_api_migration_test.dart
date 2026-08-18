import 'dart:async';
import 'dart:convert';

import 'package:astro_journal/services/api_key_service.dart';
import 'package:astro_journal/data/models/api_test_result.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/services/geocoding_service.dart';
import 'package:astro_journal/services/plate_solve/plate_solve_provider.dart';
import 'package:astro_journal/services/plate_solve_service.dart';
import 'package:astro_journal/services/plate_solve_settings_service.dart';
import 'package:astro_journal/services/tc_backend_external_api_client.dart';
import 'package:astro_journal/services/tc_backend_plate_solve_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/weather_cache_service.dart';
import 'package:astro_journal/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response utf8JsonResponse(String body, int statusCode) =>
    http.Response.bytes(
      utf8.encode(body),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tc_backend_base_url': 'https://backend.example',
      'tc_backend_enabled': true,
    });
  });

  TcBackendExternalApiClient client(
    Future<http.Response> Function(http.Request request) handler,
  ) => TcBackendExternalApiClient(
    settingsService: TcBackendSettingsService(),
    client: MockClient(handler),
    timeout: const Duration(milliseconds: 100),
  );

  test('standard backend error is decoded without exposing raw JSON', () async {
    final api = client(
      (_) async => http.Response(
        '{"detail":{"code":"API_KEY_NOT_CONFIGURED","message":"secret provider detail"}}',
        503,
      ),
    );

    await expectLater(
      api.getMap('/api/common/weather/current'),
      throwsA(
        isA<TcBackendExternalApiException>()
            .having(
              (error) => error.code,
              'code',
              TcBackendExternalApiErrorCode.apiKeyNotConfigured,
            )
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'safe message',
              isNot(contains('secret provider detail')),
            ),
      ),
    );
  });

  test('network and timeout errors stay distinguishable', () async {
    final network = client(
      (_) async => throw http.ClientException('connection refused'),
    );
    await expectLater(
      network.getMap('/api/common/readiness'),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.network,
        ),
      ),
    );

    final timeout = client((_) => Completer<http.Response>().future);
    await expectLater(
      timeout.getMap('/api/common/readiness'),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.timeout,
        ),
      ),
    );
  });

  test('reverse and forward geocoding map normalized backend DTOs', () async {
    final service = GeocodingService(
      backendClient: client((request) async {
        expect(request.url.queryParameters, isNot(contains('key')));
        if (request.url.path.endsWith('/reverse')) {
          return utf8JsonResponse(
            '{"display_name":"서울특별시 종로구","latitude":37.57,"longitude":126.98,"province":"서울특별시","city":"종로구","place_name":"광화문","provider":"google","source":"provider"}',
            200,
          );
        }
        return utf8JsonResponse(
          '{"items":[{"display_name":"서울특별시","latitude":37.5,"longitude":127.0,"province":"서울특별시","provider":"google"}]}',
          200,
        );
      }),
    );

    final reverse = await service.getLocationInfo(37.57, 126.98, 'legacy-key');
    expect(reverse?.locationName, '광화문');
    expect(reverse?.regionName, '서울특별시 종로구');
    final forward = await service.geocodeAddressAll('서울', 'legacy-key');
    expect(forward.single.latitude, 37.5);
  });

  test('Places passes one session token from autocomplete to details', () async {
    String? token;
    final service = GeocodingService(
      backendClient: client((request) async {
        if (request.url.path.endsWith('/autocomplete')) {
          token = request.url.queryParameters['session_token'];
          return utf8JsonResponse(
            '{"items":[{"place_id":"p1","main_text":"광화문","secondary_text":"서울","display_name":"광화문, 서울"}]}',
            200,
          );
        }
        if (request.url.path.endsWith('/forward')) {
          return http.Response('{"items":[]}', 200);
        }
        expect(request.url.queryParameters['session_token'], token);
        return utf8JsonResponse(
          '{"display_name":"광화문, 서울","latitude":37.57,"longitude":126.98,"place_name":"광화문","provider":"google"}',
          200,
        );
      }),
    );

    final suggestions = await service.autocompleteLocations('광화문');
    expect(token, isNotEmpty);
    final details = await service.getPlaceDetails(suggestions.single.placeId!);
    expect(details?.placeName, '광화문');
  });

  test('Places text search is mapped and provider errors stay empty', () async {
    final service = GeocodingService(
      backendClient: client((request) async {
        if (request.url.path.endsWith('/forward')) {
          return http.Response('{"items":[]}', 200);
        }
        expect(request.url.path, endsWith('/api/common/places/search'));
        return http.Response(
          '{"items":[{"display_name":"Seoul","latitude":37.5,"longitude":127.0,"provider":"google"}]}',
          200,
        );
      }),
    );
    final results = await service.searchLocationsAll('Seoul', 'legacy-key');
    expect(results.single.formattedAddress, 'Seoul');

    final unavailable = GeocodingService(
      backendClient: client(
        (_) async => http.Response(
          '{"detail":{"code":"PROVIDER_ERROR","message":"private"}}',
          502,
        ),
      ),
    );
    expect(await unavailable.searchLocationsAll('Seoul'), isEmpty);
  });

  test('weather maps backend current and forecast without appid', () async {
    final service = WeatherService(
      ApiKeyService(),
      backendClient: client((request) async {
        expect(request.url.queryParameters, isNot(contains('appid')));
        if (request.url.path.endsWith('/current')) {
          return utf8JsonResponse(
            '{"provider":"openweathermap","temperature":10,"feels_like":8,"humidity":70,"pressure":1012,"clouds":20,"wind_speed":2.5,"wind_direction":180,"description":"맑음","visibility":10000,"city_name":"서울","sunrise":"2026-08-18T20:00:00Z","sunset":"2026-08-19T10:00:00Z"}',
            200,
          );
        }
        return utf8JsonResponse(
          '{"provider":"openweathermap","items":[{"timestamp":"2026-08-19T00:00:00Z","temperature":9,"humidity":75,"clouds":40,"wind_speed":3,"visibility":9000,"precipitation_probability":0.2,"rain_volume_mm":0.5,"description":"구름","icon":"02n"}]}',
          200,
        );
      }),
    );

    final current = await service.getCurrentWeather(37.5, 127);
    final forecast = await service.getForecast(37.5, 127);
    expect(current.temperature, 10);
    expect(current.cityName, '서울');
    expect(forecast.single.pop, 20);
    expect(forecast.single.rainVolumeMm, 0.5);
  });

  test('weather cache round trip remains the offline fallback contract', () async {
    final service = WeatherService(
      ApiKeyService(),
      backendClient: client((request) async {
        if (request.url.path.endsWith('/current')) {
          return utf8JsonResponse(
            '{"provider":"openweathermap","temperature":10,"feels_like":8,"humidity":70,"pressure":1012,"clouds":20,"wind_speed":2.5,"wind_direction":180,"description":"맑음","visibility":10000,"city_name":"서울","sunrise":"2026-08-18T20:00:00Z","sunset":"2026-08-19T10:00:00Z"}',
            200,
          );
        }
        return utf8JsonResponse(
          '{"items":[{"timestamp":"2026-08-19T00:00:00Z","temperature":9,"humidity":75,"clouds":40,"wind_speed":3,"visibility":9000,"precipitation_probability":0.2,"description":"구름","icon":"02n"}]}',
          200,
        );
      }),
    );
    final weather = await service.getCurrentWeather(37.5, 127);
    final forecasts = await service.getForecast(37.5, 127);
    final cache = WeatherCacheService();
    await cache.save(
      latitude: 37.5,
      longitude: 127,
      weather: weather,
      forecasts: forecasts,
    );

    final restored = await cache.load(latitude: 37.5, longitude: 127);
    expect(restored?.weather.temperature, 10);
    expect(restored?.forecasts.single.pop, 20);
  });

  test('backend Plate Solve polls WAITING and PROCESSING to COMPLETED', () async {
    var polls = 0;
    final service = TcBackendPlateSolveService(
      client: client((request) async {
        if (request.method == 'POST') {
          expect(request.body, contains('"common_file_id":178'));
          return http.Response(
            '{"job_id":"opaque","status":"WAITING","common_file_id":178,"provider":"astrometry.net"}',
            202,
          );
        }
        polls++;
        if (polls == 1) {
          return http.Response(
            '{"job_id":"opaque","status":"PROCESSING","common_file_id":178,"provider":"astrometry.net"}',
            200,
          );
        }
        return http.Response(
          '{"job_id":"opaque","status":"COMPLETED","common_file_id":178,"provider":"astrometry.net","result":{"ra":10,"dec":20,"rotation":30,"pixel_scale":2,"field_width":1.5,"field_height":1,"parity":1}}',
          200,
        );
      }),
      pollInterval: Duration.zero,
      delay: (_) async {},
    );

    final result = await service.solve(commonFileId: 178);
    expect(polls, 2);
    expect(result.success, isTrue);
    expect(result.centerRa, 10);
    expect(result.pixelScale, 2);
    expect(result.fovWidth, 1.5);
  });

  test('backend Plate Solve FAILED is a provider error', () async {
    final service = TcBackendPlateSolveService(
      client: client(
        (_) async => http.Response(
          '{"job_id":"opaque","status":"FAILED","common_file_id":178,"provider":"astrometry.net"}',
          202,
        ),
      ),
      delay: (_) async {},
    );

    await expectLater(
      service.solve(commonFileId: 178),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.providerError,
        ),
      ),
    );
  });

  test('backend Plate Solve distinguishes timeout and network failures', () async {
    final timeoutService = TcBackendPlateSolveService(
      client: client((_) => Completer<http.Response>().future),
      delay: (_) async {},
    );
    await expectLater(
      timeoutService.solve(commonFileId: 178),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.timeout,
        ),
      ),
    );

    final networkService = TcBackendPlateSolveService(
      client: client((_) async => throw http.ClientException('offline')),
      delay: (_) async {},
    );
    await expectLater(
      networkService.solve(commonFileId: 178),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.network,
        ),
      ),
    );
  });

  test('registered files use Backend while pre-registration keeps direct fallback', () async {
    final provider = _RecordingPlateSolveProvider();
    final backend = TcBackendPlateSolveService(
      client: client(
        (request) async => http.Response(
          '{"job_id":"opaque","status":"COMPLETED","common_file_id":178,"provider":"astrometry.net","result":{"ra":10,"dec":20}}',
          request.method == 'POST' ? 202 : 200,
        ),
      ),
      delay: (_) async {},
    );
    final service = PlateSolveService(
      [provider],
      PlateSolveSettingsService(),
      backendService: backend,
    );

    final registered = await service.solve(
      imagePath: '/registered.jpg',
      commonFileId: 178,
    );
    expect(registered.success, isTrue);
    expect(provider.calls, 0);

    final preRegistration = await service.solve(imagePath: '/staged.jpg');
    expect(preRegistration.success, isTrue);
    expect(provider.calls, 1);
  });
}

class _RecordingPlateSolveProvider implements PlateSolveProvider {
  int calls = 0;

  @override
  String get id => 'direct-fallback';

  @override
  String get displayName => 'Direct fallback';

  @override
  Future<bool> get isConfigured async => true;

  @override
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    calls++;
    return PlateSolveResult.success(centerRa: 1, centerDec: 2);
  }

  @override
  Future<ApiTestResult> testConnection() async =>
      ApiTestResult.failure(message: 'not used');
}
