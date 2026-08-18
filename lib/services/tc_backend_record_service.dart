import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/backend_upload_result.dart';
import 'tc_backend_settings_service.dart';
import 'tc_backend_auth_service.dart';

abstract class TcBackendRecordMutations {
  Future<TcBackendRecordPatchResult> patchRecord(
    String recordId,
    int revision,
    Map<String, Object?> partialFields,
  );

  Future<TcBackendRecordDeleteResult> deleteRecord(String recordId);
}

class TcBackendRecordPatchResult {
  const TcBackendRecordPatchResult({
    required this.recordId,
    required this.revision,
    this.canonicalFields = const {},
  });

  final String recordId;
  final int revision;
  final Map<String, Object?> canonicalFields;
}

class TcBackendRecordDeleteResult {
  const TcBackendRecordDeleteResult({
    required this.recordId,
    required this.revision,
    required this.deletedAt,
  });

  final String recordId;
  final int revision;
  final DateTime deletedAt;
}

class TcBackendRecordException implements Exception {
  const TcBackendRecordException(
    this.type,
    this.message, {
    this.statusCode,
    this.currentRevision,
  });

  final BackendUploadErrorType type;
  final String message;
  final int? statusCode;
  final int? currentRevision;

  bool get isRetryable => type.isRetryable;
}

class TcBackendRecordService implements TcBackendRecordMutations {
  TcBackendRecordService({
    required this.settingsService,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    TcBackendAuthHeaders? authHeaders,
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final Duration requestTimeout;
  final TcBackendAuthHeaders _authHeaders;

  @override
  Future<TcBackendRecordPatchResult> patchRecord(
    String recordId,
    int revision,
    Map<String, Object?> partialFields,
  ) async {
    final baseUrl = await _configuredBaseUrl();
    final response = await _send(
      http.Request('PATCH', Uri.parse('$baseUrl/api/astro/records/$recordId'))
        ..headers.addAll(await _authHeaders.build(json: true))
        ..body = jsonEncode(<String, Object?>{
          'revision': revision,
          ...partialFields,
        }),
    );
    if (response.statusCode == 409) {
      final detail = _conflictDetail(response.body);
      throw TcBackendRecordException(
        BackendUploadErrorType.http409,
        'ObservationRecord revision conflict.',
        statusCode: 409,
        currentRevision: (detail['current_revision'] as num?)?.toInt(),
      );
    }
    final body = _responseMap(response);
    final id = _string(body['record_id'] ?? body['id']);
    final nextRevision = (body['revision'] as num?)?.toInt();
    if (id == null || nextRevision == null) {
      throw const TcBackendRecordException(
        BackendUploadErrorType.malformedResponse,
        'PATCH response is missing record_id or revision.',
      );
    }
    final canonical = Map<String, Object?>.from(body)
      ..remove('record_id')
      ..remove('id')
      ..remove('revision');
    return TcBackendRecordPatchResult(
      recordId: id,
      revision: nextRevision,
      canonicalFields: canonical,
    );
  }

  @override
  Future<TcBackendRecordDeleteResult> deleteRecord(String recordId) async {
    final baseUrl = await _configuredBaseUrl();
    final response = await _send(
      http.Request('DELETE', Uri.parse('$baseUrl/api/astro/records/$recordId'))
        ..headers.addAll(await _authHeaders.build(json: true)),
    );
    final body = _responseMap(response);
    final id = _string(body['record_id'] ?? body['id']);
    final revision = (body['revision'] as num?)?.toInt();
    final deleted = body['deleted'];
    final deletedAt = DateTime.tryParse(_string(body['deleted_at']) ?? '');
    if (id == null ||
        revision == null ||
        deleted != true ||
        deletedAt == null) {
      throw const TcBackendRecordException(
        BackendUploadErrorType.malformedResponse,
        'DELETE response is missing its tombstone fields.',
      );
    }
    return TcBackendRecordDeleteResult(
      recordId: id,
      revision: revision,
      deletedAt: deletedAt,
    );
  }

  Future<String> _configuredBaseUrl() async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const TcBackendRecordException(
        BackendUploadErrorType.notConfigured,
        'TC-Backend is not configured.',
      );
    }
    return baseUrl;
  }

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      final streamed = await _client.send(request).timeout(requestTimeout);
      return http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const TcBackendRecordException(
        BackendUploadErrorType.timeout,
        'TC-Backend request timed out.',
      );
    } on SocketException {
      throw const TcBackendRecordException(
        BackendUploadErrorType.network,
        'TC-Backend is unreachable.',
      );
    } on http.ClientException {
      throw const TcBackendRecordException(
        BackendUploadErrorType.network,
        'TC-Backend is unreachable.',
      );
    }
  }

  Map<String, dynamic> _responseMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final type = switch (response.statusCode) {
        401 => BackendUploadErrorType.unauthorized,
        409 => BackendUploadErrorType.http409,
        422 => BackendUploadErrorType.http422,
        >= 500 && <= 599 => BackendUploadErrorType.http5xx,
        _ => BackendUploadErrorType.http400,
      };
      throw TcBackendRecordException(
        type,
        'TC-Backend HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeObject(response.body);
    return decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : decoded;
  }

  Map<String, dynamic> _conflictDetail(String body) {
    try {
      final decoded = _decodeObject(body);
      return decoded['detail'] is Map
          ? Map<String, dynamic>.from(decoded['detail'] as Map)
          : decoded;
    } on TcBackendRecordException {
      return const {};
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) {
      throw const TcBackendRecordException(
        BackendUploadErrorType.malformedResponse,
        'TC-Backend response is empty.',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const TcBackendRecordException(
        BackendUploadErrorType.malformedResponse,
        'TC-Backend response is malformed.',
      );
    }
  }
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
