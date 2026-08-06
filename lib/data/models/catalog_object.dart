import 'dart:convert';

import '../../core/constants/catalog_type.dart';
import '../../core/constants/constellation_names.dart';
import '../../core/constants/database_constants.dart';
import '../../core/constants/object_type.dart';
import '../../core/formatters/catalog_metadata_format.dart';
import '../../core/utils/catalog_reference_classifier.dart';
import '../../core/utils/text_sanitizer.dart';
import '../../services/catalog_display_name_resolver.dart';
import 'exif_info.dart';

/// 전체 카탈로그 공통 모델.
class CatalogObject {
  const CatalogObject({
    required this.id,
    required this.number,
    required this.catalog,
    required this.name,
    required this.type,
    required this.constellation,
    required this.ra,
    required this.dec,
    required this.magnitude,
    this.commonName,
    this.objectType,
    this.seestarSupported = false,
    this.captured = false,
    this.capturedDate,
    this.photoUri,
    this.memo = '',
    this.exif,
    this.aliases = const [],
    this.crossCatalogRefs = const [],
    this.tags = const [],
    this.suffix,
    this.peakMonth,
    this.bestSeason,
    this.angularSize,
    this.distanceLy,
    this.description,
    this.searchKeywords,
    this.majorAxis,
    this.minorAxis,
    this.positionAngle,
    this.dataSource,
    this.isFeatured = false,
    this.displayPriority = DatabaseConstants.defaultDisplayPriority,
    this.isPrimaryCatalog = true,
    this.primaryCatalogId,
  });

  final String id;
  final int number;
  final CatalogType catalog;
  final String name;
  final String type;
  final String constellation;
  final String ra;
  final String dec;
  final String magnitude;
  final String? commonName;
  final String? objectType;
  final bool seestarSupported;
  final bool captured;
  final String? capturedDate;
  final String? photoUri;
  final String memo;
  final ExifInfo? exif;
  final List<String> aliases;

  /// 다른 천문 카탈로그 식별자 (NGC, IC, MWSC 등).
  final List<String> crossCatalogRefs;

  /// 내부 태그 목록 (검색·추천·필터용, UI 비표시).
  final List<String> tags;

  /// IC1318A 등 변형 접미사.
  final String? suffix;

  /// RA 기준 1년 중 관측·촬영에 가장 적합한 달 (1~12).
  final int? peakMonth;

  /// UI 표시용 계절 라벨 (예: "최적 7월 · 여름 (6~8월)").
  final String? bestSeason;

  /// 시각 크기 (예: "85' × 60'").
  final String? angularSize;

  /// 지구로부터의 거리 (광년).
  final double? distanceLy;

  /// 상세 설명.
  final String? description;

  /// 통합 검색 키워드 (파이프 구분).
  final String? searchKeywords;

  /// 장축 (arcmin).
  final double? majorAxis;

  /// 단축 (arcmin).
  final double? minorAxis;

  /// 위치각 (°).
  final double? positionAngle;

  /// 메타데이터 출처 (Manual, Seestar 등).
  final String? dataSource;

  /// 대표 천체 여부 (카테고리별 우선 노출용, 자동 생성).
  final bool isFeatured;

  /// 대표 천체 표시 우선순위 (작을수록 먼저, 자동 생성).
  final int displayPriority;

  /// 카탈로그 목록에 표시할 대표 Catalog 여부.
  final bool isPrimaryCatalog;

  /// 비대표 Catalog일 때 연결된 대표 Catalog ID.
  final String? primaryCatalogId;

  ObjectType get resolvedObjectType =>
      ObjectType.fromLabel(objectType ?? type);

  /// UI 표시용 분류 라벨.
  /// 표준 분류로 해석 가능하면 그 라벨을, 아니면 원본 type 값을 반환한다.
  String get displayType {
    final resolved = resolvedObjectType;
    if (resolved == ObjectType.other) return objectType ?? type;
    return resolved.label;
  }

  String get displayName {
    switch (catalog) {
      case CatalogType.messier:
        return 'M$number';
      case CatalogType.ngc:
        return 'NGC $number';
      case CatalogType.ic:
        return 'IC $number${suffix ?? ''}';
      case CatalogType.caldwell:
        return 'Caldwell $number';
      case CatalogType.sh2:
        return 'Sh2-$number';
      case CatalogType.rcw:
        return 'RCW $number';
      case CatalogType.vdb:
        return 'vdB $number';
      case CatalogType.barnard:
        return 'Barnard $number';
      case CatalogType.ldn:
        return 'LDN $number';
      case CatalogType.lbn:
        return 'LBN $number';
      case CatalogType.star:
      case CatalogType.solar:
      case CatalogType.milky:
        return name;
    }
  }

  String get displayId => displayName;

  /// 화면용 통칭 (commonName 우선, 없으면 name).
  String get displayCommonName =>
      TextSanitizer.sanitizeRequired(commonName ?? name);

  /// 카드·리스트용 대표명.
  /// 카탈로그명과 중복이면 null (검색 인덱스에는 영향 없음).
  String? get uiDisplayName => CatalogDisplayNameResolver.uiDisplayName(this);

  /// 목록·상세 이동 시 사용할 대표 Catalog ID.
  String get effectivePrimaryId => primaryCatalogId ?? id;

  /// UI 표시용 별칭 (한자 제거).
  List<String> get displayAliases => TextSanitizer.sanitizeList(aliases);

  /// UI 표시용 교차 카탈로그 참조 (한자 제거).
  List<String> get displayCrossCatalogRefs =>
      TextSanitizer.sanitizeList(crossCatalogRefs);

  /// 화면용 별자리 (IAU 한국어 정규 표기).
  String get displayConstellation => ConstellationNames.normalize(constellation);

  /// 카탈로그 상세 등에 표시할 계절 정보.
  String get displaySeason {
    if (bestSeason != null && bestSeason!.trim().isNotEmpty) {
      return bestSeason!;
    }
    return '-';
  }

  String get displayAngularSize {
    if (angularSize != null && angularSize!.trim().isNotEmpty) {
      return CatalogMetadataFormat.formatAngularSize(angularSize!);
    }
    return '-';
  }

  /// 거리 표시 문자열. 없거나 0이면 null (UI에서 숨김).
  String? get displayDistanceLy =>
      CatalogMetadataFormat.formatDistanceLy(distanceLy);

  String get displayDescription {
    final cleaned = TextSanitizer.sanitizeOptional(description);
    if (cleaned != null && cleaned.trim().isNotEmpty) {
      return cleaned;
    }
    return '-';
  }

  /// 상세 설명 카드용. 비어 있으면 null. 줄바꿈(\n) 유지.
  String? get detailDescription =>
      TextSanitizer.sanitizeMultilineOptional(description);

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colNum: number,
      DatabaseConstants.colCatalog: catalog.value,
      DatabaseConstants.colName: name,
      DatabaseConstants.colType: type,
      DatabaseConstants.colConstellation: constellation,
      DatabaseConstants.colRa: ra,
      DatabaseConstants.colDec: dec,
      DatabaseConstants.colMag: magnitude,
      DatabaseConstants.colCommonName: commonName,
      DatabaseConstants.colObjectType: objectType ?? type,
      DatabaseConstants.colSeestarSupported: seestarSupported ? 1 : 0,
      DatabaseConstants.colSuffix: suffix,
      DatabaseConstants.colCaptured: captured ? 1 : 0,
      DatabaseConstants.colCapturedDate: capturedDate,
      DatabaseConstants.colPhotoUri: photoUri,
      DatabaseConstants.colMemo: memo,
      DatabaseConstants.colExifJson:
          exif != null ? jsonEncode(exif!.toJson()) : null,
      DatabaseConstants.colAliasesJson:
          aliases.isNotEmpty ? jsonEncode(aliases) : null,
      DatabaseConstants.colCrossCatalogRefsJson: crossCatalogRefs.isNotEmpty
          ? jsonEncode(crossCatalogRefs)
          : null,
      DatabaseConstants.colTagsJson:
          tags.isNotEmpty ? jsonEncode(tags) : null,
      DatabaseConstants.colPeakMonth: peakMonth,
      DatabaseConstants.colBestSeason: bestSeason,
      DatabaseConstants.colAngularSize: angularSize,
      DatabaseConstants.colDistanceLy: distanceLy,
      DatabaseConstants.colDescription: description,
      DatabaseConstants.colSearchKeywords: searchKeywords,
      DatabaseConstants.colMajorAxis: majorAxis,
      DatabaseConstants.colMinorAxis: minorAxis,
      DatabaseConstants.colPositionAngle: positionAngle,
      DatabaseConstants.colDataSource: dataSource,
      DatabaseConstants.colIsFeatured: isFeatured ? 1 : 0,
      DatabaseConstants.colDisplayPriority: displayPriority,
      DatabaseConstants.colIsPrimaryCatalog: isPrimaryCatalog ? 1 : 0,
      DatabaseConstants.colPrimaryCatalogId: primaryCatalogId,
    };
  }

  factory CatalogObject.fromJson(
    Map<String, dynamic> json,
    CatalogType catalogType, {
    List<String> extraAliases = const [],
    List<String> extraCrossCatalogRefs = const [],
  }) {
    final jsonAliases = (json['aliases'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        const <String>[];
    final jsonCrossCatalogRefs =
        (json['crossCatalogRefs'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[];
    final split = CatalogReferenceClassifier.split([
      ...jsonAliases,
      ...jsonCrossCatalogRefs,
      ...extraAliases,
      ...extraCrossCatalogRefs,
    ]);
    final jsonTags = (json['tags'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        const <String>[];
    final objectTypeStr =
        json['objectType'] as String? ?? json['type'] as String;
    final common =
        json['commonName'] as String? ?? json['name'] as String;
    return CatalogObject(
      id: json['id'] as String,
      number: json['number'] as int,
      catalog: catalogType,
      name: TextSanitizer.sanitizeRequired(json['name'] as String?),
      type: TextSanitizer.sanitizeRequired(
        json['type'] as String? ?? objectTypeStr,
      ),
      commonName: TextSanitizer.sanitizeOptional(common),
      objectType: TextSanitizer.sanitizeOptional(objectTypeStr),
      seestarSupported: json['seestarSupported'] as bool? ?? false,
      constellation: ConstellationNames.normalize(
        json['constellation'] as String? ?? '-',
      ),
      ra: json['ra'] as String,
      dec: json['dec'] as String,
      magnitude: json['magnitude'] as String,
      suffix: json['suffix'] as String?,
      aliases: TextSanitizer.sanitizeList(split.aliases),
      crossCatalogRefs: TextSanitizer.sanitizeList(split.crossCatalogRefs),
      tags: TextSanitizer.sanitizeList(jsonTags),
      peakMonth: json['peakMonth'] as int?,
      bestSeason: TextSanitizer.sanitizeOptional(json['bestSeason'] as String?),
      angularSize: TextSanitizer.sanitizeOptional(json['angularSize'] as String?),
      distanceLy: (json['distanceLy'] as num?)?.toDouble(),
      description: TextSanitizer.sanitizeOptional(json['description'] as String?),
    );
  }

  factory CatalogObject.fromSeestarJson(Map<String, dynamic> json) {
    final catalog = CatalogType.fromValue(json['catalog'] as String);
    return CatalogObject.fromJson(json, catalog);
  }

  factory CatalogObject.fromMap(Map<String, dynamic> map) {
    final exifJson = map[DatabaseConstants.colExifJson] as String?;
    final aliasesJson = map[DatabaseConstants.colAliasesJson] as String?;
    final crossCatalogRefsJson =
        map[DatabaseConstants.colCrossCatalogRefsJson] as String?;
    final tagsJson = map[DatabaseConstants.colTagsJson] as String?;

    return CatalogObject(
      id: map[DatabaseConstants.colId] as String,
      number: map[DatabaseConstants.colNum] as int,
      catalog: CatalogType.fromValue(
        map[DatabaseConstants.colCatalog] as String,
      ),
      name: TextSanitizer.sanitizeRequired(
        map[DatabaseConstants.colName] as String?,
      ),
      type: TextSanitizer.sanitizeRequired(
        map[DatabaseConstants.colType] as String?,
      ),
      commonName: TextSanitizer.sanitizeOptional(
        map[DatabaseConstants.colCommonName] as String?,
      ),
      objectType: TextSanitizer.sanitizeOptional(
        map[DatabaseConstants.colObjectType] as String?,
      ),
      seestarSupported:
          (map[DatabaseConstants.colSeestarSupported] as int? ?? 0) == 1,
      suffix: map[DatabaseConstants.colSuffix] as String?,
      constellation: ConstellationNames.normalize(
        map[DatabaseConstants.colConstellation] as String? ?? '-',
      ),
      ra: map[DatabaseConstants.colRa] as String,
      dec: map[DatabaseConstants.colDec] as String,
      magnitude: map[DatabaseConstants.colMag] as String,
      captured: (map[DatabaseConstants.colCaptured] as int? ?? 0) == 1,
      capturedDate: map[DatabaseConstants.colCapturedDate] as String?,
      photoUri: map[DatabaseConstants.colPhotoUri] as String?,
      memo: TextSanitizer.stripHanzi(map[DatabaseConstants.colMemo] as String? ?? ''),
      exif: exifJson != null && exifJson.isNotEmpty
          ? ExifInfo.fromJson(
              jsonDecode(exifJson) as Map<String, dynamic>,
            )
          : null,
      aliases: _parseStringList(aliasesJson),
      crossCatalogRefs: _parseStringList(crossCatalogRefsJson),
      tags: _parseStringList(tagsJson),
      peakMonth: map[DatabaseConstants.colPeakMonth] as int?,
      bestSeason: TextSanitizer.sanitizeOptional(
        map[DatabaseConstants.colBestSeason] as String?,
      ),
      angularSize: TextSanitizer.sanitizeOptional(
        map[DatabaseConstants.colAngularSize] as String?,
      ),
      distanceLy: (map[DatabaseConstants.colDistanceLy] as num?)?.toDouble(),
      description: TextSanitizer.sanitizeOptional(
        map[DatabaseConstants.colDescription] as String?,
      ),
      searchKeywords: TextSanitizer.sanitizeSearchKeywords(
        map[DatabaseConstants.colSearchKeywords] as String?,
      ),
      majorAxis: (map[DatabaseConstants.colMajorAxis] as num?)?.toDouble(),
      minorAxis: (map[DatabaseConstants.colMinorAxis] as num?)?.toDouble(),
      positionAngle:
          (map[DatabaseConstants.colPositionAngle] as num?)?.toDouble(),
      dataSource: map[DatabaseConstants.colDataSource] as String?,
      isFeatured: (map[DatabaseConstants.colIsFeatured] as int? ?? 0) == 1,
      displayPriority: map[DatabaseConstants.colDisplayPriority] as int? ??
          DatabaseConstants.defaultDisplayPriority,
      isPrimaryCatalog:
          (map[DatabaseConstants.colIsPrimaryCatalog] as int? ?? 1) == 1,
      primaryCatalogId:
          map[DatabaseConstants.colPrimaryCatalogId] as String?,
    );
  }

  static List<String> _parseStringList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final data = jsonDecode(raw);
      if (data is List) {
        return TextSanitizer.sanitizeList(
          data.map((e) => e.toString()),
        );
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  CatalogObject copyWith({
    List<String>? aliases,
    List<String>? crossCatalogRefs,
    List<String>? tags,
    String? commonName,
    bool? captured,
    String? capturedDate,
    int? peakMonth,
    String? bestSeason,
    String? angularSize,
    double? distanceLy,
    String? description,
    String? searchKeywords,
    double? majorAxis,
    double? minorAxis,
    double? positionAngle,
    String? dataSource,
    bool? isFeatured,
    int? displayPriority,
    bool? isPrimaryCatalog,
    String? primaryCatalogId,
  }) {
    return CatalogObject(
      id: id,
      number: number,
      catalog: catalog,
      name: name,
      type: type,
      commonName: commonName ?? this.commonName,
      objectType: objectType,
      seestarSupported: seestarSupported,
      suffix: suffix,
      constellation: constellation,
      ra: ra,
      dec: dec,
      magnitude: magnitude,
      captured: captured ?? this.captured,
      capturedDate: capturedDate ?? this.capturedDate,
      photoUri: photoUri,
      memo: memo,
      exif: exif,
      aliases: aliases ?? this.aliases,
      crossCatalogRefs: crossCatalogRefs ?? this.crossCatalogRefs,
      tags: tags ?? this.tags,
      peakMonth: peakMonth ?? this.peakMonth,
      bestSeason: bestSeason ?? this.bestSeason,
      angularSize: angularSize ?? this.angularSize,
      distanceLy: distanceLy ?? this.distanceLy,
      description: description ?? this.description,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      majorAxis: majorAxis ?? this.majorAxis,
      minorAxis: minorAxis ?? this.minorAxis,
      positionAngle: positionAngle ?? this.positionAngle,
      dataSource: dataSource ?? this.dataSource,
      isFeatured: isFeatured ?? this.isFeatured,
      displayPriority: displayPriority ?? this.displayPriority,
      isPrimaryCatalog: isPrimaryCatalog ?? this.isPrimaryCatalog,
      primaryCatalogId: primaryCatalogId ?? this.primaryCatalogId,
    );
  }
}
