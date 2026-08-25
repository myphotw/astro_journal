import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/astrojournal_reset.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_settings_service.dart';

enum AstroJournalResetErrorType {
  blocked,
  notConfigured,
  unauthorized,
  network,
  timeout,
  http,
  malformedResponse,
}

class AstroJournalResetException implements Exception {
  const AstroJournalResetException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  final AstroJournalResetErrorType type;
  final String message;
  final int? statusCode;

  String get userMessage => switch (type) {
    AstroJournalResetErrorType.blocked =>
      '사진 처리 작업이 진행 중입니다. 작업이 끝난 뒤 다시 시도해주세요.',
    AstroJournalResetErrorType.notConfigured =>
      'Backend 연결이 준비되지 않아 촬영 데이터를 초기화할 수 없습니다.',
    AstroJournalResetErrorType.unauthorized => 'Backend 인증을 확인한 뒤 다시 시도해주세요.',
    AstroJournalResetErrorType.network => 'Backend에 연결할 수 없습니다. 네트워크를 확인해주세요.',
    AstroJournalResetErrorType.timeout =>
      'Backend 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.',
    AstroJournalResetErrorType.http ||
    AstroJournalResetErrorType.malformedResponse =>
      '촬영 데이터 초기화 요청을 완료하지 못했습니다. 잠시 후 다시 시도해주세요.',
  };

  @override
  String toString() => message;
}

abstract interface class AstroJournalResetApi {
  Future<AstroJournalResetPreview> preview();
  Future<AstroJournalResetResult> execute();
}

class TcBackendAstroJournalResetService implements AstroJournalResetApi {
  factory TcBackendAstroJournalResetService({
    required TcBackendSettingsService settingsService,
    TcBackendAuthHeaders? authHeaders,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) => TcBackendAstroJournalResetService._(
    settingsService,
    authHeaders ?? TcBackendAuthHeaders(const EmptyTcBackendTokenStore()),
    client ?? http.Client(),
    timeout,
  );

  TcBackendAstroJournalResetService._(
    this._settingsService,
    this._authHeaders,
    this._client,
    this.timeout,
  );

  static const confirmation = 'RESET_ASTROJOURNAL';

  final TcBackendSettingsService _settingsService;
  final TcBackendAuthHeaders _authHeaders;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<AstroJournalResetPreview> preview() async {
    final body = await _post('/api/astro/reset/preview', const {});
    try {
      return AstroJournalResetPreview.fromJson(body);
    } on FormatException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.malformedResponse,
        message: 'Reset preview response does not match the Backend contract.',
      );
    }
  }

  @override
  Future<AstroJournalResetResult> execute() async {
    final body = await _post('/api/astro/reset/execute', const {
      'confirmation': confirmation,
    });
    try {
      final result = AstroJournalResetResult.fromJson(body);
      if (!result.resetCompleted) throw const FormatException();
      return result;
    } on FormatException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.malformedResponse,
        message: 'Reset execute response does not match the Backend contract.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.notConfigured,
        message: 'TC-Backend is not configured.',
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: await _authHeaders.build(json: true),
            body: jsonEncode(body),
          )
          .timeout(timeout);
      final decoded = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded['detail'];
        final detailMap = detail is Map
            ? Map<String, dynamic>.from(detail)
            : decoded;
        final code = detailMap['code']?.toString();
        if (response.statusCode == 409 &&
            code == 'ASTROJOURNAL_RESET_BLOCKED') {
          throw const AstroJournalResetException(
            type: AstroJournalResetErrorType.blocked,
            message: 'AstroJournal Reset is blocked by processing jobs.',
            statusCode: 409,
          );
        }
        throw AstroJournalResetException(
          type: response.statusCode == 401
              ? AstroJournalResetErrorType.unauthorized
              : AstroJournalResetErrorType.http,
          message: 'TC-Backend HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      final data = decoded['data'];
      return data is Map ? Map<String, dynamic>.from(data) : decoded;
    } on AstroJournalResetException {
      rethrow;
    } on TimeoutException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.timeout,
        message: 'TC-Backend Reset request timed out.',
      );
    } on SocketException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.network,
        message: 'TC-Backend is unreachable.',
      );
    } on http.ClientException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.network,
        message: 'TC-Backend is unreachable.',
      );
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.malformedResponse,
        message: 'TC-Backend Reset response is empty.',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const AstroJournalResetException(
        type: AstroJournalResetErrorType.malformedResponse,
        message: 'TC-Backend Reset response is malformed.',
      );
    }
  }
}
