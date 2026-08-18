import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/gallery_item.dart';
import '../../services/tc_backend_auth_service.dart';

class RemoteGalleryException implements Exception {
  const RemoteGalleryException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'RemoteGalleryException: $message';
}

abstract class GalleryRemoteDataSource {
  Future<List<GalleryItem>> getGallery({Map<String, String>? query});
  Future<GalleryItem> getDetail(String recordId);
}

class RemoteGalleryDataSource implements GalleryRemoteDataSource {
  RemoteGalleryDataSource({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    TcBackendAuthHeaders? authHeaders,
  }) : _client = client ?? http.Client(),
       _authHeaders =
           authHeaders ??
           TcBackendAuthHeaders(const EmptyTcBackendTokenStore());

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  final TcBackendAuthHeaders _authHeaders;

  @override
  Future<List<GalleryItem>> getGallery({Map<String, String>? query}) async =>
      _items(await _get('/api/astro/gallery', query: query));

  @override
  Future<GalleryItem> getDetail(String recordId) async {
    final json = _object(
      await _get('/api/astro/gallery/${Uri.encodeComponent(recordId)}'),
    );
    return _item(json);
  }

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      final response = await _client
          .get(uri, headers: await _authHeaders.build())
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RemoteGalleryException(
          'Gallery request failed with HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      if (response.body.trim().isEmpty) {
        throw const RemoteGalleryException('Gallery response is empty.');
      }
      return jsonDecode(response.body);
    } on RemoteGalleryException {
      rethrow;
    } on TimeoutException {
      throw const RemoteGalleryException('Gallery request timed out.');
    } on SocketException {
      throw const RemoteGalleryException('Gallery backend is unreachable.');
    } on http.ClientException {
      throw const RemoteGalleryException('Gallery backend is unreachable.');
    } on FormatException {
      throw const RemoteGalleryException('Gallery response is malformed.');
    }
  }

  List<GalleryItem> _items(dynamic decoded) {
    dynamic value = decoded;
    if (value is Map) {
      value = value['items'] ?? value['results'] ?? value['data'];
      if (value is Map) {
        value = value['items'] ?? value['results'];
      }
    }
    if (value is! List) {
      throw const RemoteGalleryException('Gallery list is malformed.');
    }
    try {
      return value
          .map((item) => _item(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false);
    } on RemoteGalleryException {
      rethrow;
    } on Object {
      throw const RemoteGalleryException('Gallery item is malformed.');
    }
  }

  Map<String, dynamic> _object(dynamic decoded) {
    dynamic value = decoded;
    if (value is Map && value['data'] is Map) value = value['data'];
    if (value is! Map) {
      throw const RemoteGalleryException('Gallery response is malformed.');
    }
    return Map<String, dynamic>.from(value);
  }

  GalleryItem _item(Map<String, dynamic> json) {
    try {
      return GalleryItem.fromJson(json);
    } on FormatException {
      throw const RemoteGalleryException('Gallery item is malformed.');
    }
  }
}
