class GalleryItem {
  const GalleryItem({
    required this.backendFileId,
    this.originalFilename,
    this.thumbnailUrl,
    this.previewUrl,
    this.originalUrl,
    this.capturedAt,
    this.syncedAt,
    this.favorite = false,
    this.location,
    this.targetName,
    this.catalogObjectId,
    this.syncState,
    this.metadata = const <String, dynamic>{},
  });

  final String backendFileId;
  final String? originalFilename;
  final String? thumbnailUrl;
  final String? previewUrl;
  final String? originalUrl;
  final DateTime? capturedAt;
  final DateTime? syncedAt;
  final bool favorite;
  final String? location;
  final String? targetName;
  final String? catalogObjectId;
  final String? syncState;
  final Map<String, dynamic> metadata;

  GalleryItem copyWith({DateTime? syncedAt}) => GalleryItem(
    backendFileId: backendFileId,
    originalFilename: originalFilename,
    thumbnailUrl: thumbnailUrl,
    previewUrl: previewUrl,
    originalUrl: originalUrl,
    capturedAt: capturedAt,
    syncedAt: syncedAt ?? this.syncedAt,
    favorite: favorite,
    location: location,
    targetName: targetName,
    catalogObjectId: catalogObjectId,
    syncState: syncState,
    metadata: metadata,
  );

  Map<String, dynamic> toJson() => {
    'backend_file_id': backendFileId,
    'original_filename': originalFilename,
    'thumbnail_url': thumbnailUrl,
    'preview_url': previewUrl,
    'original_url': originalUrl,
    'captured_at': capturedAt?.toUtc().toIso8601String(),
    'last_synced_at': syncedAt?.toUtc().toIso8601String(),
    'favorite': favorite,
    'location': location,
    'target_name': targetName,
    'catalog_object_id': catalogObjectId,
    'sync_state': syncState,
    'metadata': metadata,
  };

  factory GalleryItem.fromJson(
    Map<String, dynamic> json, {
    String? baseUrl,
  }) {
    final fileId = _string(json['backend_file_id'] ?? json['file_id']);
    if (fileId == null) {
      throw const FormatException('Gallery item has no backend file ID.');
    }
    return GalleryItem(
      backendFileId: fileId,
      originalFilename: _string(
        json['original_filename'] ?? json['filename'] ?? json['name'],
      ),
      thumbnailUrl: _assetUrl(
        json['thumbnail_url'],
        baseUrl,
        fileId,
        'thumbnail',
      ),
      previewUrl: _assetUrl(
        json['preview_url'],
        baseUrl,
        fileId,
        'preview',
      ),
      originalUrl: _assetUrl(
        json['original_url'],
        baseUrl,
        fileId,
        'original',
      ),
      capturedAt: _dateTime(
        _value(json, const ['captured_at', 'capture_datetime', 'taken_at']),
      ),
      syncedAt: _dateTime(json['last_synced_at'] ?? json['synced_at']),
      favorite: _bool(
        _value(json, const ['favorite', 'is_favorite']),
      ),
      location: _string(
        _value(json, const ['location', 'location_name', 'address']),
      ),
      targetName: _string(
        _value(json, const ['target_name', 'object_name']),
      ),
      catalogObjectId: _string(
        _value(json, const ['catalog_object_id', 'target_id']),
      ),
      syncState: _string(
        _value(json, const ['sync_state', 'status']),
      ),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : Map<String, dynamic>.from(json),
    );
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    return text == null ? null : DateTime.tryParse(text)?.toLocal();
  }

  static bool _bool(Object? value) =>
      value == true || value == 1 || value?.toString().toLowerCase() == 'true';

  static Object? _value(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json[key] != null) return json[key];
    }
    for (final containerKey in const [
      'metadata',
      'observation',
      'observation_record',
      'astro',
    ]) {
      final nested = json[containerKey];
      if (nested is! Map) continue;
      for (final key in keys) {
        if (nested[key] != null) return nested[key];
      }
    }
    return null;
  }

  static String? _assetUrl(
    Object? value,
    String? baseUrl,
    String fileId,
    String variant,
  ) {
    final explicit = _string(value);
    if (explicit != null) {
      final uri = Uri.tryParse(explicit);
      if (uri != null && uri.hasScheme) return explicit;
      if (baseUrl != null && explicit.startsWith('/')) {
        return '$baseUrl$explicit';
      }
      return explicit;
    }
    return baseUrl == null
        ? null
        : '$baseUrl/api/common/gallery/${Uri.encodeComponent(fileId)}/$variant';
  }
}
