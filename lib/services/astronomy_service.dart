import 'dart:convert';

import '../data/models/api_test_result.dart';
import 'api_key_service.dart';
import 'app_logger.dart';
import 'base_api_service.dart';

/// Service for the AstronomyAPI (https://astronomyapi.com).
///
/// Authentication: HTTP Basic Auth using Application ID and Application Secret.
///
/// Planned endpoints:
/// - Search Object  GET /search
/// - Body Position  GET /bodies/positions
/// - Rise / Set     GET /bodies/events/riset
/// - Moon Phase     GET /studio/moon-phase
/// - Constellation  GET /constellations
class AstronomyService extends BaseApiService {
  AstronomyService(this._keyService)
      : super(baseUrl: 'https://api.astronomyapi.com/api/v2');

  final ApiKeyService _keyService;

  static const _tag = 'AstronomyService';

  @override
  Future<Map<String, String>> getHeaders() async {
    final base = await super.getHeaders();
    final appId = await _keyService.get(ApiKeyType.astronomyAppId);
    final appSecret = await _keyService.get(ApiKeyType.astronomyAppSecret);

    if (appId == null || appId.isEmpty || appSecret == null || appSecret.isEmpty) {
      return base;
    }

    final credentials = base64Encode(utf8.encode('$appId:$appSecret'));
    return {...base, 'Authorization': 'Basic $credentials'};
  }

  /// Verifies connectivity and authentication by requesting the bodies list.
  ///
  /// Returns an [ApiTestResult] describing success or failure.
  Future<ApiTestResult> testConnection() async {
    final hasId = await _keyService.has(ApiKeyType.astronomyAppId);
    final hasSecret = await _keyService.has(ApiKeyType.astronomyAppSecret);

    if (!hasId) {
      return ApiTestResult.failure(message: 'Application ID가 저장되어 있지 않습니다.');
    }
    if (!hasSecret) {
      return ApiTestResult.failure(
          message: 'Application Secret이 저장되어 있지 않습니다.');
    }

    try {
      final raw = await getRaw('/bodies');
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
