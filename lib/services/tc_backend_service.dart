import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/tc_backend_models.dart';
import 'tc_backend_auth_service.dart';

class TcBackendException implements Exception {
  const TcBackendException(
    this.message, {
    this.isUnreachable = false,
    this.isAuthenticationFailure = false,
    this.statusCode,
  });

  final String message;
  final bool isUnreachable;
  final bool isAuthenticationFailure;
  final int? statusCode;
}

class TcBackendService {
  TcBackendService({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    TcBackendAuthHeaders? authHeaders,
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final TcBackendAuthHeaders _authHeaders;

  Future<TcBackendHealth> getHealth() async =>
      TcBackendHealth.fromJson(await _get('/health', authenticated: false));

  Future<TcBackendCapabilities> getCapabilities() async =>
      TcBackendCapabilities.fromJson(await _get('/api/common/capabilities'));

  Future<TcBackendReadiness> getReadiness() async =>
      TcBackendReadiness.fromJson(await _get('/api/common/readiness'));

  Future<TcBackendCheckResult> checkCompatibility() async {
    try {
      final health = await getHealth();
      final capabilities = await getCapabilities();
      final readiness = await getReadiness();
      final hasAstroJournal = capabilities.supportedServices.any(
        (item) => item.toLowerCase() == 'astrojournal',
      );
      final compatible =
          hasAstroJournal &&
          capabilities.supportsServiceName == true &&
          capabilities.supportsClientFileId == true;
      if (!compatible) {
        return TcBackendCheckResult(
          status: TcBackendConnectionStatus.incompatible,
          health: health,
          capabilities: capabilities,
          readiness: readiness,
          message: 'AstroJournal 업로드 계약을 지원하지 않는 서버입니다.',
        );
      }
      return TcBackendCheckResult(
        status: health.isDegraded
            ? TcBackendConnectionStatus.degraded
            : TcBackendConnectionStatus.connected,
        health: health,
        capabilities: capabilities,
        readiness: readiness,
        message: health.isDegraded ? '연결됨 (일부 기능 제한)' : '연결됨',
      );
    } on TcBackendException catch (error) {
      return TcBackendCheckResult(
        status: error.isAuthenticationFailure
            ? TcBackendConnectionStatus.authenticationFailed
            : error.isUnreachable
            ? TcBackendConnectionStatus.unreachable
            : TcBackendConnectionStatus.degraded,
        message: error.message,
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await _client
          .get(
            uri,
            headers: authenticated
                ? await _authHeaders.build()
                : const {'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          throw const TcBackendException(
            'TC-Backend authentication failed. Check the client token.',
            isAuthenticationFailure: true,
            statusCode: 401,
          );
        }
        throw TcBackendException('서버 오류 (HTTP ${response.statusCode})');
      }
      if (response.body.isEmpty) {
        throw const TcBackendException('서버 응답이 비어 있습니다.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const TcBackendException('서버 응답 형식이 올바르지 않습니다.');
      }
      final map = Map<String, dynamic>.from(decoded);
      final data = map['data'];
      return data is Map ? Map<String, dynamic>.from(data) : map;
    } on TimeoutException {
      throw const TcBackendException('서버 응답 시간이 초과되었습니다.', isUnreachable: true);
    } on SocketException {
      throw const TcBackendException('서버에 연결할 수 없습니다.', isUnreachable: true);
    } on FormatException {
      throw const TcBackendException('서버 JSON 응답을 해석할 수 없습니다.');
    } on http.ClientException {
      throw const TcBackendException('서버에 연결할 수 없습니다.', isUnreachable: true);
    }
  }
}
