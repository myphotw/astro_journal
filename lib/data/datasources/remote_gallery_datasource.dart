import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/gallery_item.dart';
import '../../services/app_logger.dart';
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
    // Astro Gallery's `file_id` is the SHA-256 asset identity. Plate Solve
    // requires the positive CommonFile database identity exposed as `file_id`
    // by the canonical ObservationRecord API. Keep the two identities separate
    // and only enrich a detail response when Gallery did not already provide
    // `common_file_id`.
    if (_positiveInt(json['common_file_id']) == null) {
      AppLogger.info(
        'RemoteGalleryDataSource',
        'common_file_id recovery request '
            'backend_record_id=$recordId source=ObservationRecord detail',
      );
      try {
        final record = _object(
          await _get('/api/astro/records/${Uri.encodeComponent(recordId)}'),
        );
        final hasFileId = record.containsKey('file_id');
        final rawFileId = record['file_id'];
        final commonFileId = _positiveInt(rawFileId);
        AppLogger.info(
          'RemoteGalleryDataSource',
          'common_file_id recovery response '
              'backend_record_id=$recordId http=success '
              'file_id_present=$hasFileId '
              'file_id_type=${rawFileId?.runtimeType ?? "null"} '
              'parsed_common_file_id=${commonFileId ?? "null"}',
        );
        if (commonFileId != null) json['common_file_id'] = commonFileId;
      } on RemoteGalleryException catch (error) {
        AppLogger.info(
          'RemoteGalleryDataSource',
          'common_file_id recovery response '
              'backend_record_id=$recordId http=failure '
              'status_code=${error.statusCode ?? "transport_or_parse"} '
              'file_id_present=unknown file_id_type=unknown '
              'parsed_common_file_id=null',
        );
        // Gallery detail remains usable when identity recovery is unavailable.
        // Plate Solve will retain its existing pre-upload/unlinked guard.
      }
    }
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

  int? _positiveInt(Object? value) {
    if (value is num && value.toInt() > 0) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
