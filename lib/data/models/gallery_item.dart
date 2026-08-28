import 'plate_solve_queue.dart';
import 'plate_solve_result.dart';

class GalleryItem {
  const GalleryItem({
    required this.backendRecordId,
    required this.revision,
    required this.catalogObjectId,
    required this.capturedAt,
    required this.favorite,
    required this.representative,
    required this.backendFileId,
    this.commonFileId,
    this.plateSolveStatus,
    this.plateSolveJobId,
    this.plateSolve,
    required this.thumbnailUrl,
    required this.previewUrl,
    required this.originalUrl,
    this.originalFilename,
    this.mimeType,
    this.captureDatetime,
    this.latitude,
    this.longitude,
    this.location,
    this.memo = '',
    this.syncedAt,
    this.syncState,
  });

  final String backendRecordId;
  final int revision;
  final String catalogObjectId;
  final DateTime capturedAt;
  final bool favorite;
  final bool representative;
  final String backendFileId;
  final int? commonFileId;
  final PlateSolveQueueStatus? plateSolveStatus;
  final String? plateSolveJobId;
  final PlateSolveResult? plateSolve;
  final String thumbnailUrl;
  final String previewUrl;
  final String originalUrl;
  final String? originalFilename;
  final String? mimeType;
  final DateTime? captureDatetime;
  final double? latitude;
  final double? longitude;
  final String? location;
  final String memo;
  final DateTime? syncedAt;
  final String? syncState;

  GalleryItem copyWith({
    int? revision,
    PlateSolveQueueStatus? plateSolveStatus,
    String? plateSolveJobId,
    PlateSolveResult? plateSolve,
    bool? favorite,
    bool? representative,
    String? memo,
    String? location,
    bool updateLocation = false,
    double? latitude,
    bool updateLatitude = false,
    double? longitude,
    bool updateLongitude = false,
    DateTime? syncedAt,
    String? syncState,
  }) => GalleryItem(
    backendRecordId: backendRecordId,
    revision: revision ?? this.revision,
    catalogObjectId: catalogObjectId,
    capturedAt: capturedAt,
    favorite: favorite ?? this.favorite,
    representative: representative ?? this.representative,
    backendFileId: backendFileId,
    commonFileId: commonFileId,
    plateSolveStatus: plateSolveStatus ?? this.plateSolveStatus,
    plateSolveJobId: plateSolveJobId ?? this.plateSolveJobId,
    plateSolve: plateSolve ?? this.plateSolve,
    thumbnailUrl: thumbnailUrl,
    previewUrl: previewUrl,
    originalUrl: originalUrl,
    originalFilename: originalFilename,
    mimeType: mimeType,
    captureDatetime: captureDatetime,
    latitude: updateLatitude ? latitude : this.latitude,
    longitude: updateLongitude ? longitude : this.longitude,
    location: updateLocation ? location : this.location,
    memo: memo ?? this.memo,
    syncedAt: syncedAt ?? this.syncedAt,
    syncState: syncState ?? this.syncState,
  );

  Map<String, dynamic> toJson() => {
    'record_id': backendRecordId,
    'revision': revision,
    'catalog_object_id': catalogObjectId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'favorite': favorite,
    'representative': representative,
    'file_id': backendFileId,
    if (commonFileId != null) 'common_file_id': commonFileId,
    if (plateSolveStatus != null)
      'plate_solve_status': plateSolveStatus!.backendValue,
    if (plateSolveJobId != null) 'plate_solve_job_id': plateSolveJobId,
    if (plateSolve != null) 'plate_solve_result': plateSolve!.toJson(),
    'filename': originalFilename,
    'mime_type': mimeType,
    'thumbnail_url': thumbnailUrl,
    'preview_url': previewUrl,
    'original_url': originalUrl,
    'capture_datetime': captureDatetime?.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'location_name': location,
    'memo': memo,
    'last_synced_at': syncedAt?.toUtc().toIso8601String(),
    'sync_state': syncState,
  };

  factory GalleryItem.fromJson(Map<String, dynamic> json) {
    return GalleryItem(
      backendRecordId: _requiredString(json, 'record_id'),
      revision: _requiredInt(json, 'revision'),
      catalogObjectId: _requiredString(json, 'catalog_object_id'),
      capturedAt: _requiredDateTime(json, 'captured_at'),
      favorite: _requiredBool(json, 'favorite'),
      representative: _requiredBool(json, 'representative'),
      backendFileId: _requiredString(json, 'file_id'),
      commonFileId: _optionalInt(json['common_file_id']),
      plateSolveStatus: PlateSolveQueueStatus.fromJson(
        json['plate_solve_status'],
      ),
      plateSolveJobId: _string(json['plate_solve_job_id']),
      plateSolve: _plateSolveResult(json['plate_solve_result']),
      thumbnailUrl: _requiredString(json, 'thumbnail_url'),
      previewUrl: _requiredString(json, 'preview_url'),
      originalUrl: _requiredString(json, 'original_url'),
      originalFilename: _string(json['filename']),
      mimeType: _string(json['mime_type']),
      captureDatetime: _dateTime(json['capture_datetime']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      location: _string(json['location_name']),
      memo: json['memo'] as String? ?? '',
      syncedAt: _dateTime(json['last_synced_at']),
      syncState: _string(json['sync_state']),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = _string(json[key]);
    if (value == null) throw FormatException('Gallery item has no $key.');
    return value;
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toInt();
    throw FormatException('Gallery item has no valid $key.');
  }

  static int? _optionalInt(Object? value) {
    if (value is num && value.toInt() > 0) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static bool _requiredBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    if (value == 0 || value == 1) return value == 1;
    throw FormatException('Gallery item has no valid $key.');
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _dateTime(json[key]);
    if (value == null) throw FormatException('Gallery item has no valid $key.');
    return value;
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    return text == null ? null : DateTime.tryParse(text)?.toLocal();
  }

  static PlateSolveResult? _plateSolveResult(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    if (json.containsKey('status') || json.containsKey('centerRa')) {
      return PlateSolveResult.fromJson(json);
    }
    return PlateSolveResult.fromJson({
      'status': PlateSolveStatus.success.name,
      'centerRa': _double(json['ra']),
      'centerDec': _double(json['dec']),
      'rotation': _double(json['rotation']),
      'pixelScale': _double(json['pixel_scale']),
      'fovWidth': _double(json['field_width']),
      'fovHeight': _double(json['field_height']),
      'parity': _double(json['parity']),
    });
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
