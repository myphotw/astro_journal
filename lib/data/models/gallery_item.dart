import 'dart:convert';

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
    this.equipmentRefId,
    this.equipmentName,
    this.equipmentNameSnapshot,
    this.equipmentIsActive,
    this.equipmentDeleted,
    this.equipmentFieldsPresent = false,
    this.integrationSeconds,
    this.integrationSecondsPresent = false,
    this.address,
    this.addressPresent = false,
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
  final String? equipmentRefId;
  final String? equipmentName;
  final String? equipmentNameSnapshot;
  final bool? equipmentIsActive;
  final bool? equipmentDeleted;

  /// 구버전 Gallery cache의 필드 누락과 서버의 명시적 null을 구분한다.
  final bool equipmentFieldsPresent;
  final int? integrationSeconds;
  final bool integrationSecondsPresent;
  final String? address;
  final bool addressPresent;
  final String memo;
  final DateTime? syncedAt;
  final String? syncState;

  GalleryItem copyWith({
    int? revision,
    String? catalogObjectId,
    bool updateCatalogObjectId = false,
    DateTime? capturedAt,
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
    String? equipmentRefId,
    bool updateEquipmentRefId = false,
    String? equipmentName,
    bool updateEquipmentName = false,
    String? equipmentNameSnapshot,
    bool updateEquipmentNameSnapshot = false,
    bool? equipmentIsActive,
    bool updateEquipmentIsActive = false,
    bool? equipmentDeleted,
    bool updateEquipmentDeleted = false,
    int? integrationSeconds,
    bool updateIntegrationSeconds = false,
    String? address,
    bool updateAddress = false,
    DateTime? syncedAt,
    String? syncState,
  }) => GalleryItem(
    backendRecordId: backendRecordId,
    revision: revision ?? this.revision,
    catalogObjectId: updateCatalogObjectId
        ? (catalogObjectId ?? this.catalogObjectId)
        : this.catalogObjectId,
    capturedAt: capturedAt ?? this.capturedAt,
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
    equipmentRefId: updateEquipmentRefId
        ? equipmentRefId
        : this.equipmentRefId,
    equipmentName: updateEquipmentName ? equipmentName : this.equipmentName,
    equipmentNameSnapshot: updateEquipmentNameSnapshot
        ? equipmentNameSnapshot
        : this.equipmentNameSnapshot,
    equipmentIsActive: updateEquipmentIsActive
        ? equipmentIsActive
        : this.equipmentIsActive,
    equipmentDeleted: updateEquipmentDeleted
        ? equipmentDeleted
        : this.equipmentDeleted,
    equipmentFieldsPresent:
        equipmentFieldsPresent ||
        updateEquipmentRefId ||
        updateEquipmentName ||
        updateEquipmentNameSnapshot ||
        updateEquipmentIsActive ||
        updateEquipmentDeleted,
    integrationSeconds: updateIntegrationSeconds
        ? integrationSeconds
        : this.integrationSeconds,
    integrationSecondsPresent:
        integrationSecondsPresent || updateIntegrationSeconds,
    address: updateAddress ? address : this.address,
    addressPresent: addressPresent || updateAddress,
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
    if (equipmentFieldsPresent) ...{
      'equipment_ref_id': equipmentRefId,
      'equipment_name': equipmentName,
      'equipment_name_snapshot': equipmentNameSnapshot,
      'equipment_is_active': equipmentIsActive,
      'equipment_deleted': equipmentDeleted,
    },
    if (integrationSecondsPresent)
      'integration_seconds': integrationSeconds,
    if (addressPresent) 'address': address,
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
      equipmentRefId: _string(json['equipment_ref_id']),
      equipmentName: _string(json['equipment_name']),
      equipmentNameSnapshot: _string(json['equipment_name_snapshot']),
      equipmentIsActive: _optionalBool(json['equipment_is_active']),
      equipmentDeleted: _optionalBool(json['equipment_deleted']),
      equipmentFieldsPresent:
          json.containsKey('equipment_ref_id') ||
          json.containsKey('equipment_name') ||
          json.containsKey('equipment_name_snapshot') ||
          json.containsKey('equipment_is_active') ||
          json.containsKey('equipment_deleted'),
      integrationSeconds: _optionalNonNegativeInt(
        json['integration_seconds'],
      ),
      integrationSecondsPresent: json.containsKey('integration_seconds'),
      address: _string(json['address']),
      addressPresent: json.containsKey('address'),
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

  static bool? _optionalBool(Object? value) {
    if (value is bool) return value;
    if (value == 0 || value == 1) return value == 1;
    return null;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
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
      return PlateSolveResult.fromJson({
        ...json,
        'rawWcsJson': json['rawWcsJson'] ?? jsonEncode(json),
      });
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
      'imageWidth': _optionalInt(json['image_width']),
      'imageHeight': _optionalInt(json['image_height']),
      'wcs': json['wcs'] ?? json['fits_wcs'] ?? json['fitsWcs'],
      'rawWcsJson': jsonEncode(json),
    });
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
