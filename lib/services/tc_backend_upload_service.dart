import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../data/models/backend_upload_result.dart';
import '../data/models/shooting_record.dart';
import 'tc_backend_settings_service.dart';

/// Best-effort A2 adapter. It deliberately has no SQLite/outbox dependency.
class TcBackendUploadService {
  TcBackendUploadService({
    required this.settingsService,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxPollDuration = const Duration(seconds: 45),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final TcBackendSettingsService settingsService;
  final http.Client _client;
  final Duration requestTimeout;
  final Duration maxPollDuration;
  final Future<void> Function(Duration) _delay;
  final Map<String, _HashCacheEntry> _hashCache = {};

  Future<BackendUploadResult> uploadRecord(ShootingRecord record) async {
    final settings = await settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled) return const BackendUploadResult.notAttempted();
    if (baseUrl == null ||
        record.photoUri == null ||
        record.photoUri!.isEmpty) {
      return const BackendUploadResult(
        attempted: false,
        success: false,
        errorType: BackendUploadErrorType.notConfigured,
        errorMessage: 'TC-Backend address or local photo is unavailable.',
      );
    }

    final clientFileId = const Uuid().v4();
    String? sha256;
    String? jobId;
    String? backendFileId;
    try {
      final file = File(record.photoUri!);
      if (!await file.exists()) {
        return BackendUploadResult(
          attempted: true,
          success: false,
          clientFileId: clientFileId,
          errorType: BackendUploadErrorType.uploadRejected,
          errorMessage: 'Local photo file is unavailable.',
        );
      }
      sha256 = await contentSha256(file);
      final upload = await _upload(baseUrl, file, clientFileId, sha256);
      jobId = upload.jobId;
      backendFileId = upload.backendFileId;
      if (backendFileId == null) {
        backendFileId = await _pollForFileId(baseUrl, jobId);
      }
      final created = await _createRecord(baseUrl, backendFileId, record);
      return BackendUploadResult(
        attempted: true,
        success: true,
        clientFileId: clientFileId,
        contentSha256: sha256,
        uploadJobId: jobId,
        backendFileId: backendFileId,
        backendRecordId: created.id,
        recordRevision: created.revision,
      );
    } on _UploadException catch (error) {
      return BackendUploadResult(
        attempted: true,
        success: false,
        clientFileId: clientFileId,
        contentSha256: sha256,
        uploadJobId: jobId,
        backendFileId: backendFileId,
        errorType: error.type,
        errorMessage: error.message,
      );
    } catch (_) {
      return BackendUploadResult(
        attempted: true,
        success: false,
        clientFileId: clientFileId,
        contentSha256: sha256,
        uploadJobId: jobId,
        backendFileId: backendFileId,
        errorType: BackendUploadErrorType.unreachable,
        errorMessage: 'TC-Backend connection failed.',
      );
    }
  }

  Future<String> contentSha256(File file) async {
    final stat = await file.stat();
    final cached = _hashCache[file.path];
    if (cached != null &&
        cached.length == stat.size &&
        cached.modified == stat.modified)
      return cached.value;
    final sink = _DigestSink();
    final converter = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    final value = sink.value!.toString();
    _hashCache[file.path] = _HashCacheEntry(stat.size, stat.modified, value);
    return value;
  }

  Future<_UploadResponse> _upload(
    String baseUrl,
    File file,
    String clientFileId,
    String sha256,
  ) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/common/upload'))
          ..headers['Accept'] = 'application/json'
          ..fields['service_name'] = 'AstroJournal'
          ..fields['client_file_id'] = clientFileId
          ..fields['client_content_sha256'] = sha256
          ..files.add(
            await http.MultipartFile.fromPath(
              'file',
              file.path,
              filename: path.basename(file.path),
            ),
          );
    final response = await _send(request);
    if (response.statusCode == 409) {
      throw const _UploadException(
        BackendUploadErrorType.idempotencyConflict,
        'Upload idempotency conflict.',
      );
    }
    final json = _responseMap(response, BackendUploadErrorType.uploadRejected);
    final jobId = _string(json['job_id']);
    if (jobId == null) {
      throw const _UploadException(
        BackendUploadErrorType.malformedResponse,
        'Upload response has no job_id.',
      );
    }
    return _UploadResponse(jobId, _string(json['backend_file_id']));
  }

  Future<String> _pollForFileId(String baseUrl, String jobId) async {
    final started = DateTime.now();
    var interval = const Duration(seconds: 1);
    while (DateTime.now().difference(started) < maxPollDuration) {
      await _delay(interval);
      final response = await _get(
        Uri.parse('$baseUrl/api/common/upload/jobs/$jobId'),
      );
      final map = _responseMap(response, BackendUploadErrorType.jobFailed);
      final status = _string(map['status'])?.toUpperCase();
      if (status == 'COMPLETED') {
        final id = _string(map['backend_file_id'] ?? map['file_id']);
        if (id == null) {
          throw const _UploadException(
            BackendUploadErrorType.malformedResponse,
            'Completed upload has no backend_file_id.',
          );
        }
        return id;
      }
      if (status == 'FAILED') {
        throw _UploadException(
          BackendUploadErrorType.jobFailed,
          _string(map['error_message']) ?? 'Upload job failed.',
        );
      }
      if (status != 'WAITING' && status != 'PROCESSING') {
        throw const _UploadException(
          BackendUploadErrorType.malformedResponse,
          'Unknown upload job status.',
        );
      }
      interval = const Duration(seconds: 2);
    }
    throw const _UploadException(
      BackendUploadErrorType.jobTimeout,
      'Upload job timed out.',
    );
  }

  Future<_RecordResponse> _createRecord(
    String baseUrl,
    String backendFileId,
    ShootingRecord record,
  ) async {
    final payload = observationRecordPayload(record, backendFileId);
    final request =
        http.Request('POST', Uri.parse('$baseUrl/api/astro/records'))
          ..headers.addAll(const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(payload);
    final response = await _send(request);
    final map = _responseMap(
      response,
      BackendUploadErrorType.recordCreateFailed,
    );
    final id = _string(map['record_id'] ?? map['id']);
    if (id == null) {
      throw const _UploadException(
        BackendUploadErrorType.malformedResponse,
        'ObservationRecord response has no record ID.',
      );
    }
    final revision = (map['revision'] as num?)?.toInt();
    return _RecordResponse(id, revision);
  }

  Map<String, dynamic> observationRecordPayload(
    ShootingRecord record,
    String backendFileId,
  ) => <String, dynamic>{
    'file_id': backendFileId,
    'catalog_object_id': record.celestialObjectId,
    'captured_at': record.capturedAt.toUtc().toIso8601String(),
    'latitude': record.exif?.lat,
    'longitude': record.exif?.lng,
    'location_name': record.location ?? record.exif?.locationName,
    'memo': record.memo,
    'favorite': record.isFavorite,
    'representative': record.isRepresentative,
    'equipment_id': null,
  };

  Future<http.Response> _send(http.BaseRequest request) async {
    try {
      final response = await _client.send(request).timeout(requestTimeout);
      return http.Response.fromStream(response);
    } on TimeoutException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend request timed out.',
      );
    } on SocketException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend is unreachable.',
      );
    } on http.ClientException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend is unreachable.',
      );
    }
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend request timed out.',
      );
    } on SocketException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend is unreachable.',
      );
    } on http.ClientException {
      throw const _UploadException(
        BackendUploadErrorType.unreachable,
        'TC-Backend is unreachable.',
      );
    }
  }

  Map<String, dynamic> _responseMap(
    http.Response response,
    BackendUploadErrorType errorType,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _UploadException(
        errorType,
        'TC-Backend HTTP ${response.statusCode}.',
      );
    }
    if (response.body.isEmpty) {
      throw const _UploadException(
        BackendUploadErrorType.malformedResponse,
        'TC-Backend response is empty.',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      final map = Map<String, dynamic>.from(decoded);
      return map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;
    } on FormatException {
      throw const _UploadException(
        BackendUploadErrorType.malformedResponse,
        'TC-Backend response is malformed.',
      );
    }
  }
}

String? _string(Object? value) =>
    value?.toString().trim().isEmpty ?? true ? null : value.toString();

class _HashCacheEntry {
  const _HashCacheEntry(this.length, this.modified, this.value);
  final int length;
  final DateTime modified;
  final String value;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _UploadResponse {
  const _UploadResponse(this.jobId, this.backendFileId);
  final String jobId;
  final String? backendFileId;
}

class _RecordResponse {
  const _RecordResponse(this.id, this.revision);
  final String id;
  final int? revision;
}

class _UploadException implements Exception {
  const _UploadException(this.type, this.message);
  final BackendUploadErrorType type;
  final String message;
}
