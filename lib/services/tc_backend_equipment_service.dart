import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/equipment.dart';
import '../data/models/equipment_remote.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_settings_service.dart';

enum EquipmentRemoteErrorType {
  notConfigured,
  network,
  timeout,
  unauthorized,
  notFound,
  conflict,
  invalidRequest,
  server,
  malformedResponse,
}

extension EquipmentRemoteErrorPolicy on EquipmentRemoteErrorType {
  bool get isRetryable => switch (this) {
    EquipmentRemoteErrorType.network ||
    EquipmentRemoteErrorType.timeout ||
    EquipmentRemoteErrorType.server => true,
    _ => false,
  };
}

class EquipmentRemoteException implements Exception {
  const EquipmentRemoteException({
    required this.type,
    required this.message,
    this.statusCode,
    this.currentRevision,
  });

  final EquipmentRemoteErrorType type;
  final String message;
  final int? statusCode;
  final int? currentRevision;

  bool get isRetryable => type.isRetryable;

  @override
  String toString() => message;
}

abstract interface class EquipmentRemoteApi {
  Future<List<EquipmentRemoteAggregate>> list();
  Future<EquipmentRemoteAggregate> get(String equipmentId);
  Future<EquipmentRemoteAggregate> create(Equipment equipment);
  Future<EquipmentRemoteAggregate> update(
    Equipment equipment, {
    required int expectedRevision,
  });
  Future<EquipmentRemoteDeleteResult> delete(
    String equipmentId, {
    required int expectedRevision,
  });
}

class TcBackendEquipmentService implements EquipmentRemoteApi {
  TcBackendEquipmentService({
    required this.settingsService,
    http.Client? client,
    TcBackendAuthHeaders? authHeaders,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  static const path = '/api/astro/equipment';

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final TcBackendAuthHeaders _authHeaders;
  final Duration timeout;

  @override
  Future<List<EquipmentRemoteAggregate>> list() async {
    final response = await _send('GET', await _uri(path));
    final decoded = _decode(response.body);
    if (decoded is! List) {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment list response is not an array.',
      );
    }
    try {
      return decoded
          .map((item) {
            if (item is! Map) throw const FormatException();
            return EquipmentRemoteAggregate.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment list item is malformed: $error',
      );
    }
  }

  @override
  Future<EquipmentRemoteAggregate> get(String equipmentId) async {
    final response = await _send('GET', await _uri('$path/$equipmentId'));
    return _aggregate(response.body);
  }

  @override
  Future<EquipmentRemoteAggregate> create(Equipment equipment) async {
    final now = DateTime.now().toUtc();
    final body = EquipmentRemoteAggregate(
      equipment: equipment,
      revision: 0,
      createdAt: now,
      updatedAt: now,
    ).toCreateJson();
    return _aggregate((await _send('POST', await _uri(path), body: body)).body);
  }

  @override
  Future<EquipmentRemoteAggregate> update(
    Equipment equipment, {
    required int expectedRevision,
  }) async {
    final now = DateTime.now().toUtc();
    final body = EquipmentRemoteAggregate(
      equipment: equipment,
      revision: expectedRevision,
      createdAt: now,
      updatedAt: now,
    ).toPatchJson(expectedRevision: expectedRevision);
    return _aggregate(
      (await _send(
        'PATCH',
        await _uri('$path/${equipment.id}'),
        body: body,
      )).body,
    );
  }

  @override
  Future<EquipmentRemoteDeleteResult> delete(
    String equipmentId, {
    required int expectedRevision,
  }) async {
    final uri = (await _uri(
      '$path/$equipmentId',
    )).replace(queryParameters: {'expected_revision': '$expectedRevision'});
    try {
      return EquipmentRemoteDeleteResult.fromJson(
        _object((await _send('DELETE', uri)).body),
      );
    } on FormatException catch (error) {
      throw EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment delete response is malformed: $error',
      );
    }
  }

  Future<Uri> _uri(String endpoint) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.notConfigured,
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
    } on EquipmentRemoteException {
      rethrow;
    } on TimeoutException {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.timeout,
        message: 'Equipment request timed out.',
      );
    } on SocketException {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.network,
        message: 'Equipment backend is unreachable.',
      );
    } on http.ClientException {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.network,
        message: 'Equipment backend is unreachable.',
      );
    }
  }

  EquipmentRemoteAggregate _aggregate(String body) {
    try {
      return EquipmentRemoteAggregate.fromJson(_object(body));
    } on FormatException catch (error) {
      throw EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment response is malformed: $error',
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
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment response is empty.',
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const EquipmentRemoteException(
        type: EquipmentRemoteErrorType.malformedResponse,
        message: 'Equipment response is invalid JSON.',
      );
    }
  }

  EquipmentRemoteException _httpError(http.Response response) {
    final detail = _errorDetail(response.body);
    final type = switch (response.statusCode) {
      401 || 403 => EquipmentRemoteErrorType.unauthorized,
      404 => EquipmentRemoteErrorType.notFound,
      409 => EquipmentRemoteErrorType.conflict,
      >= 500 && <= 599 => EquipmentRemoteErrorType.server,
      _ => EquipmentRemoteErrorType.invalidRequest,
    };
    return EquipmentRemoteException(
      type: type,
      message:
          detail['code']?.toString() ??
          'Equipment request failed with HTTP ${response.statusCode}.',
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
