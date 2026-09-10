import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/multi_night_framing_reference.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_settings_service.dart';

enum MultiNightFramingRemoteErrorType {
  notConfigured,
  network,
  timeout,
  unauthorized,
  notFound,
  revisionConflict,
  referenceAlreadyExists,
  conflict,
  invalidRequest,
  server,
  malformedResponse,
}

extension MultiNightFramingRemoteErrorPolicy
    on MultiNightFramingRemoteErrorType {
  bool get isRetryable => switch (this) {
    MultiNightFramingRemoteErrorType.network ||
    MultiNightFramingRemoteErrorType.timeout ||
    MultiNightFramingRemoteErrorType.server => true,
    _ => false,
  };
}

class MultiNightFramingRemoteException implements Exception {
  const MultiNightFramingRemoteException({
    required this.type,
    required this.message,
    this.statusCode,
    this.currentRevision,
  });

  final MultiNightFramingRemoteErrorType type;
  final String message;
  final int? statusCode;
  final int? currentRevision;

  bool get isRetryable => type.isRetryable;

  @override
  String toString() => message;
}

abstract interface class MultiNightFramingRemoteApi {
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  });
  Future<MultiNightFramingReference> get(String referenceId);
  Future<MultiNightFramingReference> create(
    MultiNightFramingReference reference,
  );
  Future<MultiNightFramingReference> update(
    MultiNightFramingReference reference, {
    required int expectedRevision,
  });
  Future<MultiNightFramingDeleteResult> delete(
    String referenceId, {
    required int expectedRevision,
  });
}

class TcBackendMultiNightFramingService implements MultiNightFramingRemoteApi {
  TcBackendMultiNightFramingService({
    required this.settingsService,
    http.Client? client,
    TcBackendAuthHeaders? authHeaders,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  static const path = '/api/astro/multi-night-framing-references';

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final TcBackendAuthHeaders _authHeaders;
  final Duration timeout;

  @override
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  }) async {
    final query = <String, String>{
      if (catalogObjectId != null) 'catalog_object_id': catalogObjectId,
      if (equipmentId != null) 'equipment_id': equipmentId,
    };
    final uri = (await _uri(
      path,
    )).replace(queryParameters: query.isEmpty ? null : query);
    final decoded = _decode((await _send('GET', uri)).body);
    if (decoded is! List) {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference list response is not an array.',
      );
    }
    try {
      return decoded
          .map((item) {
            if (item is! Map) throw const FormatException();
            return MultiNightFramingReference.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference list item is malformed: $error',
      );
    }
  }

  @override
  Future<MultiNightFramingReference> get(String referenceId) async =>
      _reference((await _send('GET', await _uri('$path/$referenceId'))).body);

  @override
  Future<MultiNightFramingReference> create(
    MultiNightFramingReference reference,
  ) async => _reference(
    (await _send(
      'POST',
      await _uri(path),
      body: reference.toCreateJson(),
    )).body,
  );

  @override
  Future<MultiNightFramingReference> update(
    MultiNightFramingReference reference, {
    required int expectedRevision,
  }) async => _reference(
    (await _send(
      'PATCH',
      await _uri('$path/${reference.id}'),
      body: reference.toPatchJson(expectedRevision: expectedRevision),
    )).body,
  );

  @override
  Future<MultiNightFramingDeleteResult> delete(
    String referenceId, {
    required int expectedRevision,
  }) async {
    final uri = (await _uri(
      '$path/$referenceId',
    )).replace(queryParameters: {'expected_revision': '$expectedRevision'});
    try {
      return MultiNightFramingDeleteResult.fromJson(
        _object((await _send('DELETE', uri)).body),
      );
    } on FormatException catch (error) {
      throw MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference delete response is malformed: $error',
      );
    }
  }

  Future<Uri> _uri(String endpoint) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.notConfigured,
        message: 'TC-Backend is not configured.',
      );
    }
    return Uri.parse('$baseUrl$endpoint');
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(await _authHeaders.build(json: body != null));
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response);
      }
      return response;
    } on MultiNightFramingRemoteException {
      rethrow;
    } on TimeoutException {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.timeout,
        message: 'Multi-night reference request timed out.',
      );
    } on SocketException {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.network,
        message: 'Multi-night reference backend is unreachable.',
      );
    } on http.ClientException {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.network,
        message: 'Multi-night reference backend is unreachable.',
      );
    }
  }

  MultiNightFramingReference _reference(String body) {
    try {
      return MultiNightFramingReference.fromJson(_object(body));
    } on FormatException catch (error) {
      throw MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference response is malformed: $error',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final decoded = _decode(body);
    if (decoded is! Map) throw const FormatException('JSON object expected.');
    return Map<String, dynamic>.from(decoded);
  }

  Object? _decode(String body) {
    if (body.trim().isEmpty) {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference response is empty.',
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const MultiNightFramingRemoteException(
        type: MultiNightFramingRemoteErrorType.malformedResponse,
        message: 'Multi-night reference response is invalid JSON.',
      );
    }
  }

  MultiNightFramingRemoteException _httpError(http.Response response) {
    final detail = _errorDetail(response.body);
    final code = detail['code']?.toString();
    final type = switch (response.statusCode) {
      401 || 403 => MultiNightFramingRemoteErrorType.unauthorized,
      404 => MultiNightFramingRemoteErrorType.notFound,
      409 when code == 'REVISION_CONFLICT' =>
        MultiNightFramingRemoteErrorType.revisionConflict,
      409 when code == 'REFERENCE_ALREADY_EXISTS' =>
        MultiNightFramingRemoteErrorType.referenceAlreadyExists,
      409 => MultiNightFramingRemoteErrorType.conflict,
      >= 500 && <= 599 => MultiNightFramingRemoteErrorType.server,
      _ => MultiNightFramingRemoteErrorType.invalidRequest,
    };
    return MultiNightFramingRemoteException(
      type: type,
      message:
          code ??
          'Multi-night reference request failed with HTTP ${response.statusCode}.',
      statusCode: response.statusCode,
      currentRevision: (detail['current_revision'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> _errorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const {};
      final map = Map<String, dynamic>.from(decoded);
      return map['detail'] is Map
          ? Map<String, dynamic>.from(map['detail'] as Map)
          : map;
    } on FormatException {
      return const {};
    }
  }
}
