class GalleryItem {
  const GalleryItem({
    required this.backendRecordId,
    required this.revision,
    required this.catalogObjectId,
    required this.capturedAt,
    required this.favorite,
    required this.representative,
    required this.backendFileId,
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
    bool? favorite,
    bool? representative,
    String? memo,
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
    thumbnailUrl: thumbnailUrl,
    previewUrl: previewUrl,
    originalUrl: originalUrl,
    originalFilename: originalFilename,
    mimeType: mimeType,
    captureDatetime: captureDatetime,
    latitude: latitude,
    longitude: longitude,
    location: location,
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
}
