import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// Thrown when an API request fails with a non-2xx response or network error.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode != null
      ? 'ApiException[$statusCode]: $message'
      : 'ApiException: $message';
}

/// Container for a raw API response including timing metadata.
class RawApiResponse {
  const RawApiResponse({
    required this.data,
    required this.statusCode,
    required this.elapsedMs,
  });

  final Map<String, dynamic> data;
  final int statusCode;
  final int elapsedMs;
}

/// Abstract base class for all API services in the application.
///
/// Provides:
/// - [get] / [post] convenience methods returning parsed JSON
/// - [getRaw] / [postRaw] returning [RawApiResponse] with status + timing
/// - Automatic request/response debug logging via [AppLogger]
/// - Configurable [timeout] and server-error [maxRetries]
///
/// Subclasses implement [getHeaders] to supply authentication headers.
/// The method is `async` so credentials can be loaded from secure storage.
abstract class BaseApiService {
  const BaseApiService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 1,
  });

  final String baseUrl;
  final Duration timeout;

  /// Number of additional attempts on server errors (5xx). Default 1.
  final int maxRetries;

  /// Returns headers for every request, including auth.
  ///
  /// Override in subclasses to inject API-key or Basic-Auth headers.
  Future<Map<String, String>> getHeaders() async => {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      };

  // ── Public convenience API ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final raw = await getRaw(path, queryParams: queryParams);
    return raw.data;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final raw = await postRaw(path, body);
    return raw.data;
  }

  Future<RawApiResponse> getRaw(
    String path, {
    Map<String, String>? queryParams,
  }) =>
      _withRetry(() => _doGet(path, queryParams: queryParams));

  Future<RawApiResponse> postRaw(
    String path,
    Map<String, dynamic> body,
  ) =>
      _withRetry(() => _doPost(path, body));

  // ── Internal implementation ────────────────────────────────────────────────

  Future<RawApiResponse> _doGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final headers = await getHeaders();
    final uri =
        Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
    AppLogger.request('GET', uri.toString(), headers: headers);

    final sw = Stopwatch()..start();
    try {
      final response =
          await http.get(uri, headers: headers).timeout(timeout);
      sw.stop();
      AppLogger.response(
        uri.toString(),
        response.statusCode,
        response.body,
        elapsedMs: sw.elapsedMilliseconds,
      );
      return RawApiResponse(
        data: _parse(response),
        statusCode: response.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      sw.stop();
      AppLogger.error(path, 'Timeout after ${timeout.inSeconds}s');
      throw const ApiException('요청 시간이 초과되었습니다.');
    } on SocketException catch (e) {
      sw.stop();
      AppLogger.error(path, e);
      throw ApiException('네트워크 오류: ${e.message}');
    }
  }

  Future<RawApiResponse> _doPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await getHeaders();
    final uri = Uri.parse('$baseUrl$path');
    AppLogger.request('POST', uri.toString(), headers: headers);

    final sw = Stopwatch()..start();
    try {
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      sw.stop();
      AppLogger.response(
        uri.toString(),
        response.statusCode,
        response.body,
        elapsedMs: sw.elapsedMilliseconds,
      );
      return RawApiResponse(
        data: _parse(response),
        statusCode: response.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      sw.stop();
      AppLogger.error(path, 'Timeout after ${timeout.inSeconds}s');
      throw const ApiException('요청 시간이 초과되었습니다.');
    } on SocketException catch (e) {
      sw.stop();
      AppLogger.error(path, e);
      throw ApiException('네트워크 오류: ${e.message}');
    }
  }

  Map<String, dynamic> _parse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'data': decoded};
      } catch (_) {
        return {'raw': response.body};
      }
    }
    throw ApiException(
      response.body.isNotEmpty
          ? response.body
          : 'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } on ApiException catch (e) {
        // Only retry on server errors (5xx); surface client errors immediately.
        if (attempt >= maxRetries ||
            e.statusCode == null ||
            e.statusCode! < 500) {
          rethrow;
        }
        attempt++;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }
}
