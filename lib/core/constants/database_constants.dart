class DatabaseConstants {
  DatabaseConstants._();

  static const String databaseName = 'astro_journal.db';
  static const int databaseVersion = 31;

  /// 대표 천체 표시 우선순위 기본값 (미분류).
  static const int defaultDisplayPriority = 9999;

  static const String tableCelestialObjects = 'celestial_objects';
  static const String tableCelestialObjectsFts = 'celestial_objects_fts';
  static const String tableShootingRecords = 'shooting_records';
  static const String tablePhotos = 'photos';
  static const String tableEquipment = 'equipment';
  static const String tableEyepieces = 'eyepieces';
  static const String tableObservationSiteFavorites =
      'observation_site_favorites';
  static const String tablePhotoObjects = 'photo_objects';
  static const String tableSyncOutbox = 'sync_outbox';
  static const String tableGalleryCache = 'gallery_cache';

  static const String colId = 'id';
  static const String colNum = 'num';
  static const String colCatalog = 'catalog';
  static const String colName = 'name';
  static const String colType = 'type';
  static const String colConstellation = 'constellation';
  static const String colRa = 'ra';
  static const String colDec = 'dec';
  static const String colMag = 'mag';
  static const String colCaptured = 'captured';
  static const String colCapturedDate = 'captured_date';
  static const String colPhotoUri = 'photo_uri';
  static const String colMemo = 'memo';
  static const String colExifJson = 'exif_json';

  static const String colCelestialObjectId = 'celestial_object_id';
  static const String colCapturedAt = 'captured_at';
  static const String colCreatedAt = 'created_at';

  static const String colLocalPath = 'local_path';
  static const String colLocation = 'location';
  static const String colMetadataJson = 'metadata_json';
  static const String colPlateSolveJson = 'plate_solve_json';
  static const String colDetectMethod = 'detect_method';
  static const String colAnalysisStatus = 'analysis_status';
  static const String colOriginalFilename = 'original_filename';
  static const String colIsRepresentative = 'is_representative';
  static const String colIsFavorite = 'is_favorite';
  static const String colAliasesJson = 'aliases_json';
  static const String colCrossCatalogRefsJson = 'cross_catalog_refs_json';
  static const String colTagsJson = 'tags_json';
  static const String colCommonName = 'common_name';
  static const String colObjectType = 'object_type';
  static const String colSeestarSupported = 'seestar_supported';
  static const String colSuffix = 'suffix';
  static const String colPeakMonth = 'peak_month';
  static const String colBestSeason = 'best_season';
  static const String colAngularSize = 'angular_size';
  static const String colDistanceLy = 'distance_ly';
  static const String colDescription = 'description';
  static const String colSearchKeywords = 'search_keywords';
  static const String colMajorAxis = 'major_axis';
  static const String colMinorAxis = 'minor_axis';
  static const String colPositionAngle = 'position_angle';
  static const String colDataSource = 'data_source';
  static const String colIsFeatured = 'is_featured';
  static const String colDisplayPriority = 'display_priority';
  static const String colIsPrimaryCatalog = 'is_primary_catalog';
  static const String colPrimaryCatalogId = 'primary_catalog_id';

  static const String colFtsObjectId = 'object_id';
  static const String colFtsSearchText = 'search_text';

  static const String colEquipmentKind = 'equipment_kind';
  static const String colEquipmentPurpose = 'equipment_purpose';
  static const String colIsActive = 'is_active';
  static const String colFocalLengthMm = 'focal_length_mm';
  static const String colFovDegrees = 'fov_degrees';
  static const String colFovWidthDegrees = 'fov_width_degrees';
  static const String colFovHeightDegrees = 'fov_height_degrees';
  static const String colApertureMm = 'aperture_mm';
  static const String colSortOrder = 'sort_order';
  static const String colEquipmentId = 'equipment_id';
  static const String colAfovDegrees = 'afov_degrees';
  static const String colLatitude = 'latitude';
  static const String colLongitude = 'longitude';
  static const String colBortle = 'bortle';
  static const String colSqm = 'sqm';
  static const String colBrightnessGrade = 'brightness_grade';

  /// photo_objects (WCS 기반 사진 속 천체 검색 결과) 전용 컬럼.
  static const String colPhotoId = 'photo_id';
  static const String colCatalogId = 'catalog_id';
  static const String colCatalogType = 'catalog_type';
  static const String colDisplayName = 'display_name';
  static const String colAngularDistance = 'angular_distance';
  static const String colConfidence = 'confidence';
  static const String colIsPrimaryTarget = 'is_primary_target';
  static const String colIsVisible = 'is_visible';
  static const String colPixelX = 'pixel_x';
  static const String colPixelY = 'pixel_y';

  /// 카탈로그 데이터 변경 시 증가 (import 재실행 트리거).
  static const int catalogDataVersion = 28;

  /// 카탈로그 목록용 경량 컬럼 (상세/메타데이터 제외).
  static const List<String> celestialObjectListColumns = [
    colId,
    colNum,
    colCatalog,
    colName,
    colType,
    colConstellation,
    colRa,
    colDec,
    colMag,
    colCaptured,
    colCapturedDate,
    colPhotoUri,
    colAliasesJson,
    colCommonName,
    colObjectType,
    colSeestarSupported,
    colPeakMonth,
    colBestSeason,
    colAngularSize,
    colIsFeatured,
    colDisplayPriority,
    colIsPrimaryCatalog,
    colPrimaryCatalogId,
  ];

  /// celestial_objects 전체 컬럼 (SELECT * 대신 명시적 조회).
  static const List<String> celestialObjectColumns = [
    colId,
    colNum,
    colCatalog,
    colName,
    colType,
    colConstellation,
    colRa,
    colDec,
    colMag,
    colCaptured,
    colCapturedDate,
    colPhotoUri,
    colMemo,
    colExifJson,
    colAliasesJson,
    colCrossCatalogRefsJson,
    colCommonName,
    colObjectType,
    colSeestarSupported,
    colSuffix,
    colTagsJson,
    colPeakMonth,
    colBestSeason,
    colAngularSize,
    colDistanceLy,
    colDescription,
    colSearchKeywords,
    colMajorAxis,
    colMinorAxis,
    colPositionAngle,
    colDataSource,
    colIsFeatured,
    colDisplayPriority,
    colIsPrimaryCatalog,
    colPrimaryCatalogId,
  ];

  /// shooting_records 전체 컬럼.
  static const List<String> shootingRecordColumns = [
    colId,
    colCelestialObjectId,
    colCapturedAt,
    colPhotoUri,
    colOriginalFilename,
    colMemo,
    colLocation,
    colExifJson,
    colMetadataJson,
    colCreatedAt,
    colIsRepresentative,
    colIsFavorite,
    colPlateSolveJson,
    colDetectMethod,
    colAnalysisStatus,
  ];

  /// photo_objects 전체 컬럼.
  static const List<String> photoObjectColumns = [
    colId,
    colPhotoId,
    colCatalogId,
    colCatalogType,
    colDisplayName,
    colRa,
    colDec,
    colAngularDistance,
    colConfidence,
    colIsPrimaryTarget,
    colIsVisible,
    colPixelX,
    colPixelY,
    colCreatedAt,
  ];
}
