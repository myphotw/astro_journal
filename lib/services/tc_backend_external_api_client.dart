import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'tc_backend_settings_service.dart';
import 'tc_backend_auth_service.dart';

enum TcBackendExternalApiErrorCode {
  apiKeyNotConfigured,
  apiLimitExceeded,
  providerTimeout,
  providerError,
  invalidRequest,
  backendDisabled,
  network,
  timeout,
  malformedResponse,
  unknown,
  unauthorized,
}

class TcBackendExternalApiException implements Exception {
  const TcBackendExternalApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final TcBackendExternalApiErrorCode code;
  final String message;
  final int? statusCode;

  bool get allowsCachedFallback => switch (code) {
    TcBackendExternalApiErrorCode.apiKeyNotConfigured ||
    TcBackendExternalApiErrorCode.apiLimitExceeded ||
    TcBackendExternalApiErrorCode.providerTimeout ||
    TcBackendExternalApiErrorCode.providerError ||
    TcBackendExternalApiErrorCode.backendDisabled ||
    TcBackendExternalApiErrorCode.network ||
    TcBackendExternalApiErrorCode.timeout => true,
    _ => false,
  };

  @override
  String toString() => message;
}

/// Shared transport for TC-Backend hosted external APIs.
///
/// Provider credentials never enter this client. It only sends feature input
/// to the configured TC-Backend URL and decodes the normalized public contract.
class TcBackendExternalApiClient {
  TcBackendExternalApiClient({
    required this.settingsService,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    TcBackendAuthHeaders? authHeaders,
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final Duration timeout;
  final TcBackendAuthHeaders _authHeaders;

  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _send('GET', path, query: query);
    return _asMap(response);
  }

  Future<Map<String, dynamic>> postMap(
    String path, {
    required Map<String, Object?> body,
  }) async {
    final response = await _send('POST', path, body: body);
    return _asMap(response);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.backendDisabled,
        message: 'TC-Backend가 비활성화되어 있거나 주소가 설정되지 않았습니다.',
      );
    }

    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      final headers = await _authHeaders.build(json: method == 'POST');
      late final http.Response response;
      if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      } else {
        response = await _client.get(uri, headers: headers).timeout(timeout);
      }

      Object? decoded;
      if (response.body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          throw TcBackendExternalApiException(
            code: TcBackendExternalApiErrorCode.malformedResponse,
            message: 'TC-Backend 응답 형식이 올바르지 않습니다.',
            statusCode: response.statusCode,
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response.statusCode, decoded);
      }
      if (decoded == null) {
        throw TcBackendExternalApiException(
          code: TcBackendExternalApiErrorCode.malformedResponse,
          message: 'TC-Backend 응답이 비어 있습니다.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TcBackendExternalApiException {
      rethrow;
    } on TimeoutException {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.timeout,
        message: 'TC-Backend 응답 시간이 초과되었습니다.',
      );
    } on SocketException {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.network,
        message: 'TC-Backend에 연결할 수 없습니다.',
      );
    } on http.ClientException {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.network,
        message: 'TC-Backend에 연결할 수 없습니다.',
      );
    }
  }

  Map<String, dynamic> _asMap(Object? decoded) {
    if (decoded is! Map) {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: 'TC-Backend 응답이 JSON 객체가 아닙니다.',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final data = map['data'];
    return data is Map ? Map<String, dynamic>.from(data) : map;
  }

  TcBackendExternalApiException _httpError(int statusCode, Object? decoded) {
    Map<String, dynamic> detail = const {};
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final rawDetail = map['detail'];
      detail = rawDetail is Map ? Map<String, dynamic>.from(rawDetail) : map;
    }
    final rawCode = detail['code']?.toString().toUpperCase();
    final code = statusCode == 401
        ? TcBackendExternalApiErrorCode.unauthorized
        : switch (rawCode) {
            'API_KEY_NOT_CONFIGURED' =>
              TcBackendExternalApiErrorCode.apiKeyNotConfigured,
            'API_LIMIT_EXCEEDED' =>
              TcBackendExternalApiErrorCode.apiLimitExceeded,
            'PROVIDER_TIMEOUT' => TcBackendExternalApiErrorCode.providerTimeout,
            'PROVIDER_ERROR' => TcBackendExternalApiErrorCode.providerError,
            'INVALID_REQUEST' => TcBackendExternalApiErrorCode.invalidRequest,
            _ when statusCode == 429 =>
              TcBackendExternalApiErrorCode.apiLimitExceeded,
            _ when statusCode == 504 =>
              TcBackendExternalApiErrorCode.providerTimeout,
            _ when statusCode >= 500 =>
              TcBackendExternalApiErrorCode.providerError,
            _ when statusCode >= 400 && statusCode < 500 =>
              TcBackendExternalApiErrorCode.invalidRequest,
            _ => TcBackendExternalApiErrorCode.unknown,
          };
    final backendMessage = detail['message']?.toString().trim();
    return TcBackendExternalApiException(
      code: code,
      message: _safeMessage(code, backendMessage),
      statusCode: statusCode,
    );
  }

  String _safeMessage(
    TcBackendExternalApiErrorCode code,
    String? backendMessage,
  ) => switch (code) {
    TcBackendExternalApiErrorCode.apiKeyNotConfigured =>
      'TC-Backend에 해당 외부 API 키가 설정되지 않았습니다.',
    TcBackendExternalApiErrorCode.apiLimitExceeded => '외부 API 사용 한도를 초과했습니다.',
    TcBackendExternalApiErrorCode.providerTimeout =>
      '외부 API 제공자의 응답 시간이 초과되었습니다.',
    TcBackendExternalApiErrorCode.providerError => '외부 API 제공자 요청에 실패했습니다.',
    TcBackendExternalApiErrorCode.invalidRequest =>
      backendMessage?.isNotEmpty == true ? backendMessage! : '요청 값이 올바르지 않습니다.',
    _ => 'TC-Backend 요청에 실패했습니다.',
  };
}
