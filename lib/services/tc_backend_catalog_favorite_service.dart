import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/models/catalog_favorite.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_settings_service.dart';

enum CatalogFavoriteRemoteErrorType {
  notConfigured,
  network,
  timeout,
  unauthorized,
  invalidRequest,
  server,
  malformedResponse,
}

class CatalogFavoriteRemoteException implements Exception {
  const CatalogFavoriteRemoteException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  final CatalogFavoriteRemoteErrorType type;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class CatalogFavoriteRemoteApi {
  Future<List<CatalogFavorite>> list();
  Future<CatalogFavorite> add(String catalogObjectId);
  Future<CatalogFavoriteDeleteResult> remove(String catalogObjectId);
}

class TcBackendCatalogFavoriteService implements CatalogFavoriteRemoteApi {
  TcBackendCatalogFavoriteService({
    required this.settingsService,
    http.Client? client,
    TcBackendAuthHeaders? authHeaders,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  static const path = '/api/astro/catalog-favorites';

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final TcBackendAuthHeaders _authHeaders;
  final Duration timeout;

  @override
  Future<List<CatalogFavorite>> list() async {
    final decoded = _decode((await _send('GET', await _uri(path))).body);
    if (decoded is! List) {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.malformedResponse,
        message: '즐겨찾기 목록 응답 형식이 올바르지 않습니다.',
      );
    }
    try {
      return decoded
          .map((item) {
            if (item is! Map) throw const FormatException();
            return CatalogFavorite.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false);
    } on FormatException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.malformedResponse,
        message: '즐겨찾기 목록 항목을 해석할 수 없습니다.',
      );
    }
  }

  @override
  Future<CatalogFavorite> add(String catalogObjectId) async {
    final response = await _send(
      'POST',
      await _uri(path),
      body: {'catalog_object_id': catalogObjectId},
    );
    return CatalogFavorite.fromJson(_object(response.body));
  }

  @override
  Future<CatalogFavoriteDeleteResult> remove(String catalogObjectId) async {
    final encodedId = Uri.encodeComponent(catalogObjectId);
    final response = await _send('DELETE', await _uri('$path/$encodedId'));
    return CatalogFavoriteDeleteResult.fromJson(_object(response.body));
  }

  Future<Uri> _uri(String endpoint) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.notConfigured,
        message: '즐겨찾기를 변경하려면 NAS 서버 연결이 필요합니다.',
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
    } on CatalogFavoriteRemoteException {
      rethrow;
    } on TimeoutException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.timeout,
        message: 'NAS 서버의 즐겨찾기 응답 시간이 초과되었습니다.',
      );
    } on SocketException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.network,
        message: 'NAS 서버에 연결할 수 없습니다.',
      );
    } on http.ClientException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.network,
        message: 'NAS 서버에 연결할 수 없습니다.',
      );
    } on FormatException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.malformedResponse,
        message: '즐겨찾기 서버 응답을 해석할 수 없습니다.',
      );
    }
  }

  Object? _decode(String body) {
    if (body.trim().isEmpty) {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.malformedResponse,
        message: '즐겨찾기 서버 응답이 비어 있습니다.',
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const CatalogFavoriteRemoteException(
        type: CatalogFavoriteRemoteErrorType.malformedResponse,
        message: '즐겨찾기 서버 응답이 올바른 JSON이 아닙니다.',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final decoded = _decode(body);
    if (decoded is! Map) throw const FormatException();
    return Map<String, dynamic>.from(decoded);
  }

  CatalogFavoriteRemoteException _httpError(http.Response response) {
    final type = switch (response.statusCode) {
      401 || 403 => CatalogFavoriteRemoteErrorType.unauthorized,
      >= 500 && <= 599 => CatalogFavoriteRemoteErrorType.server,
      _ => CatalogFavoriteRemoteErrorType.invalidRequest,
    };
    return CatalogFavoriteRemoteException(
      type: type,
      message: switch (type) {
        CatalogFavoriteRemoteErrorType.unauthorized => 'NAS 서버 인증에 실패했습니다.',
        CatalogFavoriteRemoteErrorType.server => 'NAS 서버에서 즐겨찾기를 처리하지 못했습니다.',
        _ => '즐겨찾기 요청이 거부되었습니다. (HTTP ${response.statusCode})',
      },
      statusCode: response.statusCode,
    );
  }
}
