import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/datasources/remote_gallery_datasource.dart';
import '../data/models/gallery_item.dart';
import '../data/models/tc_backend_change.dart';
import 'tc_backend_settings_service.dart';

abstract class TcBackendChangesApi {
  Future<TcBackendChangesPage> getChanges({String? cursor});
  Future<GalleryItem> getObservationRecord(String recordId);
}

class TcBackendChangesException implements Exception {
  const TcBackendChangesException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

class TcBackendChangesService implements TcBackendChangesApi {
  TcBackendChangesService({
    required this.settingsService,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  static const serviceName = 'AstroJournal';

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<TcBackendChangesPage> getChanges({String? cursor}) async {
    final baseUrl = await _baseUrl();
    final query = <String, String>{'service_name': serviceName};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final decoded = await _get(
      Uri.parse('$baseUrl/api/common/changes').replace(queryParameters: query),
    );
    dynamic body = decoded;
    if (body is Map && body['data'] is Map) body = body['data'];
    if (body is! Map) {
      throw const TcBackendChangesException('Changes response is malformed.');
    }
    final rawChanges = body['changes'] ?? body['items'] ?? body['events'];
    if (rawChanges is! List) {
      throw const TcBackendChangesException('Changes list is missing.');
    }
    final changes = <TcBackendChange>[];
    try {
      for (final raw in rawChanges) {
        if (raw is! Map) throw const FormatException();
        changes.add(_change(Map<String, dynamic>.from(raw)));
      }
    } on FormatException {
      throw const TcBackendChangesException('Change item is malformed.');
    }
    final nextCursor = _string(body['next_cursor'] ?? body['cursor']);
    final hasMoreValue = body['has_more'];
    final hasMore = hasMoreValue is bool
        ? hasMoreValue
        : hasMoreValue == 1 || hasMoreValue == 'true';
    if (hasMore && (nextCursor == null || nextCursor == cursor)) {
      throw const TcBackendChangesException(
        'Changes pagination cursor did not advance.',
      );
    }
    return TcBackendChangesPage(
      changes: changes,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<GalleryItem> getObservationRecord(String recordId) async {
    final baseUrl = await _baseUrl();
    try {
      return await RemoteGalleryDataSource(
        baseUrl: baseUrl,
        client: _client,
        timeout: timeout,
      ).getDetail(recordId);
    } on RemoteGalleryException catch (error) {
      throw TcBackendChangesException(
        error.message,
        statusCode: error.statusCode,
      );
    }
  }

  TcBackendChange _change(Map<String, dynamic> json) {
    final resourceType = _string(
      json['resource_type'] ?? json['resource'] ?? json['entity_type'],
    );
    final resourceId = _string(
      json['resource_id'] ?? json['record_id'] ?? json['entity_id'],
    );
    final rawOperation = _string(
      json['operation'] ?? json['change_type'] ?? json['action'],
    )?.toUpperCase();
    final operation = switch (rawOperation) {
      'CREATE' || 'CREATED' => TcBackendChangeOperation.create,
      'UPDATE' || 'UPDATED' || 'UPSERT' => TcBackendChangeOperation.update,
      'DELETE' || 'DELETED' => TcBackendChangeOperation.delete,
      _ => throw const FormatException(),
    };
    if (resourceType == null || resourceId == null) {
      throw const FormatException();
    }
    return TcBackendChange(
      resourceType: resourceType,
      resourceId: resourceId,
      operation: operation,
      revision: (json['revision'] as num?)?.toInt(),
      deletedAt: DateTime.tryParse(_string(json['deleted_at']) ?? ''),
    );
  }

  Future<String> _baseUrl() async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || baseUrl == null) {
      throw const TcBackendChangesException('TC-Backend is not configured.');
    }
    return baseUrl;
  }

  Future<dynamic> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TcBackendChangesException(
          'Changes request failed with HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      if (response.body.trim().isEmpty) {
        throw const TcBackendChangesException('Changes response is empty.');
      }
      return jsonDecode(response.body);
    } on TcBackendChangesException {
      rethrow;
    } on TimeoutException {
      throw const TcBackendChangesException('Changes request timed out.');
    } on SocketException {
      throw const TcBackendChangesException('Changes backend is unreachable.');
    } on http.ClientException {
      throw const TcBackendChangesException('Changes backend is unreachable.');
    } on FormatException {
      throw const TcBackendChangesException('Changes response is malformed.');
    }
  }
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
