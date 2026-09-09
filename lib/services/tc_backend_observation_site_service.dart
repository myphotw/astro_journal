import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/observation_site.dart';
import '../data/models/observation_site_remote.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_settings_service.dart';

enum ObservationSiteRemoteErrorType {
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

extension ObservationSiteRemoteErrorPolicy on ObservationSiteRemoteErrorType {
  bool get isRetryable => switch (this) {
    ObservationSiteRemoteErrorType.network ||
    ObservationSiteRemoteErrorType.timeout ||
    ObservationSiteRemoteErrorType.server => true,
    _ => false,
  };
}

class ObservationSiteRemoteException implements Exception {
  const ObservationSiteRemoteException({
    required this.type,
    required this.message,
    this.statusCode,
    this.currentRevision,
  });

  final ObservationSiteRemoteErrorType type;
  final String message;
  final int? statusCode;
  final int? currentRevision;

  bool get isRetryable => type.isRetryable;

  @override
  String toString() => message;
}

abstract interface class ObservationSiteRemoteApi {
  Future<List<ObservationSiteRemoteAggregate>> list();
  Future<ObservationSiteRemoteAggregate> get(String siteId);
  Future<ObservationSiteRemoteAggregate> create(ObservationSite site);
  Future<ObservationSiteRemoteAggregate> update(
    ObservationSite site, {
    required int expectedRevision,
  });
  Future<ObservationSiteRemoteDeleteResult> delete(
    String siteId, {
    required int expectedRevision,
  });
}

class TcBackendObservationSiteService implements ObservationSiteRemoteApi {
  TcBackendObservationSiteService({
    required this.settingsService,
    http.Client? client,
    TcBackendAuthHeaders? authHeaders,
    this.timeout = const Duration(seconds: 20),
    this.includeDefaultEquipmentId = true,
    this.canReferenceDefaultEquipment,
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  static const path = '/api/astro/observation-sites';

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final TcBackendAuthHeaders _authHeaders;
  final Duration timeout;

  /// A non-null reference is emitted only after Equipment sync has established
  /// that UUID on the server. Null remains explicit so a deleted default can be
  /// cleared canonically.
  final bool includeDefaultEquipmentId;
  final Future<bool> Function(String equipmentId)? canReferenceDefaultEquipment;

  @override
  Future<List<ObservationSiteRemoteAggregate>> list() async {
    final response = await _send('GET', await _uri(path));
    final decoded = _decode(response.body);
    final raw = decoded is Map && decoded['data'] is List
        ? decoded['data']
        : decoded;
    if (raw is! List) {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite list response is not an array.',
      );
    }
    try {
      return raw
          .map((item) {
            if (item is! Map) throw const FormatException();
            return ObservationSiteRemoteAggregate.fromJson(
              Map<String, dynamic>.from(item),
            );
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite list item is malformed: $error',
      );
    }
  }

  @override
  Future<ObservationSiteRemoteAggregate> get(String siteId) async {
    final response = await _send('GET', await _uri('$path/$siteId'));
    return _aggregate(response.body);
  }

  @override
  Future<ObservationSiteRemoteAggregate> create(ObservationSite site) async {
    final includeDefault = await _shouldIncludeDefaultEquipment(site);
    final body = ObservationSiteRemoteAggregate(
      site: site,
      revision: 0,
    ).toCreateJson(includeDefaultEquipmentId: includeDefault);
    final response = await _send('POST', await _uri(path), body: body);
    return _aggregate(response.body);
  }

  @override
  Future<ObservationSiteRemoteAggregate> update(
    ObservationSite site, {
    required int expectedRevision,
  }) async {
    final includeDefault = await _shouldIncludeDefaultEquipment(site);
    final body = ObservationSiteRemoteAggregate(site: site, revision: 0)
        .toPatchJson(
          expectedRevision: expectedRevision,
          includeDefaultEquipmentId: includeDefault,
        );
    final response = await _send(
      'PATCH',
      await _uri('$path/${site.id}'),
      body: body,
    );
    return _aggregate(response.body);
  }

  Future<bool> _shouldIncludeDefaultEquipment(ObservationSite site) async {
    if (!includeDefaultEquipmentId) return false;
    final equipmentId = site.defaultEquipmentId;
    if (equipmentId == null) return true;
    final predicate = canReferenceDefaultEquipment;
    return predicate == null || await predicate(equipmentId);
  }

  @override
  Future<ObservationSiteRemoteDeleteResult> delete(
    String siteId, {
    required int expectedRevision,
  }) async {
    final uri = (await _uri(
      '$path/$siteId',
    )).replace(queryParameters: {'expected_revision': '$expectedRevision'});
    final response = await _send('DELETE', uri);
    try {
      return ObservationSiteRemoteDeleteResult.fromJson(_object(response.body));
    } on FormatException catch (error) {
      throw ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite delete response is malformed: $error',
      );
    }
  }

  Future<Uri> _uri(String endpoint) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.notConfigured,
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
    } on ObservationSiteRemoteException {
      rethrow;
    } on TimeoutException {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.timeout,
        message: 'ObservationSite request timed out.',
      );
    } on SocketException {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.network,
        message: 'ObservationSite backend is unreachable.',
      );
    } on http.ClientException {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.network,
        message: 'ObservationSite backend is unreachable.',
      );
    }
  }

  ObservationSiteRemoteAggregate _aggregate(String body) {
    try {
      return ObservationSiteRemoteAggregate.fromJson(_object(body));
    } on FormatException catch (error) {
      throw ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite response is malformed: $error',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final decoded = _decode(body);
    final raw = decoded is Map && decoded['data'] is Map
        ? decoded['data']
        : decoded;
    if (raw is! Map) throw const FormatException('JSON object expected.');
    return Map<String, dynamic>.from(raw);
  }

  Object? _decode(String body) {
    if (body.trim().isEmpty) {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite response is empty.',
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const ObservationSiteRemoteException(
        type: ObservationSiteRemoteErrorType.malformedResponse,
        message: 'ObservationSite response is invalid JSON.',
      );
    }
  }

  ObservationSiteRemoteException _httpError(http.Response response) {
    final detail = _errorDetail(response.body);
    final type = switch (response.statusCode) {
      401 || 403 => ObservationSiteRemoteErrorType.unauthorized,
      404 => ObservationSiteRemoteErrorType.notFound,
      409 => ObservationSiteRemoteErrorType.conflict,
      >= 500 && <= 599 => ObservationSiteRemoteErrorType.server,
      _ => ObservationSiteRemoteErrorType.invalidRequest,
    };
    return ObservationSiteRemoteException(
      type: type,
      message:
          detail['code']?.toString() ??
          'ObservationSite request failed with HTTP ${response.statusCode}.',
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
