import 'dart:convert';

import '../../core/constants/analysis_status.dart';
import '../../core/constants/database_constants.dart';
import '../../core/constants/detect_method.dart';
import 'exif_info.dart';
import 'plate_solve_queue.dart';
import 'plate_solve_result.dart';

/// 천체 촬영 기록 모델.
class ShootingRecord {
  const ShootingRecord({
    required this.id,
    required this.celestialObjectId,
    required this.capturedAt,
    this.photoUri,
    this.originalFilename,
    this.memo = '',
    this.location,
    this.exif,
    this.metadataJson,
    required this.createdAt,
    this.isRepresentative = false,
    this.isFavorite = false,
    this.plateSolve,
    this.detectMethod,
    this.analysisStatus = AnalysisStatus.completed,
    this.backendRecordId,
    this.backendRevision,
    this.backendFileId,
    this.commonFileId,
    this.plateSolveQueueStatus,
    this.plateSolveJobId,
    this.thumbnailUrl,
    this.previewUrl,
    this.originalUrl,
    this.syncState,
    this.remoteTargetName,
  });

  final String id;
  final String celestialObjectId;
  final DateTime capturedAt;
  final String? photoUri;

  /// 갤러리 원본 파일명 (UUID 저장 경로와 별도).
  final String? originalFilename;
  final String memo;
  final String? location;
  final ExifInfo? exif;

  /// OwnerName JSON 원본 문자열 (Seestar 전용, 향후 확장 대비).
  final String? metadataJson;

  final DateTime createdAt;

  /// 갤러리·카탈로그 목록에 표시할 대표사진 여부.
  final bool isRepresentative;

  /// 사용자 즐겨찾기 여부.
  final bool isFavorite;

  /// Plate Solve 결과 (WCS). 미실행 시 null.
  final PlateSolveResult? plateSolve;

  /// 촬영 대상을 어떤 방식으로 식별했는지 (EXIF/FILENAME/PLATE_SOLVE/MANUAL).
  /// 구버전 기록(도입 이전)은 null.
  final DetectMethod? detectMethod;

  /// 대상 자동 분석(Plate Solve) 진행 상태. 대상은 저장 전 항상 사용자가
  /// 확인·확정하므로, 이 값은 "대상이 맞는지"가 아니라 백그라운드 Plate
  /// Solve 분석 진행도를 나타낸다.
  final AnalysisStatus analysisStatus;

  /// Remote Gallery fields are transient projection data and are not written
  /// into the V1 shooting_records table.
  final String? backendFileId;
  final int? commonFileId;
  final PlateSolveQueueStatus? plateSolveQueueStatus;
  final String? plateSolveJobId;
  final String? backendRecordId;
  final int? backendRevision;
  final String? thumbnailUrl;
  final String? previewUrl;
  final String? originalUrl;
  final String? syncState;
  final String? remoteTargetName;

  bool get isRemoteAsset => backendFileId != null;
  String? get galleryThumbnailUri => thumbnailUrl ?? photoUri;
  String? get galleryPreviewUri => previewUrl ?? originalUrl ?? photoUri;

  /// Plate Solve 성공 여부 (Gallery 표시용 편의 getter).
  bool get isPlateSolved => plateSolve?.success ?? false;

  /// Plate Solve 진행 상태. 아직 실행한 적이 없으면 [PlateSolveStatus.none].
  PlateSolveStatus get plateSolveStatus =>
      plateSolve?.status ?? PlateSolveStatus.none;

  /// Plate Solve로 얻은 중심 RA (degrees). 미실행/실패 시 null.
  double? get solveRa => plateSolve?.centerRa;

  /// Plate Solve로 얻은 중심 DEC (degrees). 미실행/실패 시 null.
  double? get solveDec => plateSolve?.centerDec;

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colCelestialObjectId: celestialObjectId,
      DatabaseConstants.colCapturedAt: capturedAt.toIso8601String(),
      DatabaseConstants.colPhotoUri: photoUri,
      DatabaseConstants.colOriginalFilename: originalFilename,
      DatabaseConstants.colMemo: memo,
      DatabaseConstants.colLocation: location,
      DatabaseConstants.colExifJson: exif != null
          ? jsonEncode(exif!.toJson())
          : null,
      DatabaseConstants.colMetadataJson: metadataJson,
      DatabaseConstants.colCreatedAt: createdAt.toIso8601String(),
      DatabaseConstants.colIsRepresentative: isRepresentative ? 1 : 0,
      DatabaseConstants.colIsFavorite: isFavorite ? 1 : 0,
      DatabaseConstants.colPlateSolveJson: plateSolve != null
          ? PlateSolveResult.encode(plateSolve!)
          : null,
      DatabaseConstants.colDetectMethod: detectMethod?.value,
      DatabaseConstants.colAnalysisStatus: analysisStatus.value,
    };
  }

  factory ShootingRecord.fromMap(Map<String, dynamic> map) {
    final exifJson = map[DatabaseConstants.colExifJson] as String?;

    return ShootingRecord(
      id: map[DatabaseConstants.colId] as String,
      celestialObjectId: map[DatabaseConstants.colCelestialObjectId] as String,
      capturedAt: DateTime.parse(
        map[DatabaseConstants.colCapturedAt] as String,
      ),
      photoUri: map[DatabaseConstants.colPhotoUri] as String?,
      originalFilename: map[DatabaseConstants.colOriginalFilename] as String?,
      memo: map[DatabaseConstants.colMemo] as String? ?? '',
      location: map[DatabaseConstants.colLocation] as String?,
      exif: exifJson != null && exifJson.isNotEmpty
          ? ExifInfo.fromJson(jsonDecode(exifJson) as Map<String, dynamic>)
          : null,
      metadataJson: map[DatabaseConstants.colMetadataJson] as String?,
      createdAt: DateTime.parse(map[DatabaseConstants.colCreatedAt] as String),
      isRepresentative:
          (map[DatabaseConstants.colIsRepresentative] as int? ?? 0) == 1,
      isFavorite: (map[DatabaseConstants.colIsFavorite] as int? ?? 0) == 1,
      plateSolve: PlateSolveResult.decode(
        map[DatabaseConstants.colPlateSolveJson] as String?,
      ),
      detectMethod: DetectMethod.fromValue(
        map[DatabaseConstants.colDetectMethod] as String?,
      ),
      analysisStatus: AnalysisStatus.fromValue(
        map[DatabaseConstants.colAnalysisStatus] as String?,
      ),
    );
  }

  ShootingRecord copyWith({
    String? id,
    String? celestialObjectId,
    DateTime? capturedAt,
    String? photoUri,
    String? originalFilename,
    String? memo,
    String? location,
    bool clearLocation = false,
    ExifInfo? exif,
    String? metadataJson,
    DateTime? createdAt,
    bool? isRepresentative,
    bool? isFavorite,
    PlateSolveResult? plateSolve,
    bool clearPlateSolve = false,
    DetectMethod? detectMethod,
    AnalysisStatus? analysisStatus,
    String? backendRecordId,
    int? backendRevision,
    String? backendFileId,
    int? commonFileId,
    PlateSolveQueueStatus? plateSolveQueueStatus,
    String? plateSolveJobId,
    String? thumbnailUrl,
    String? previewUrl,
    String? originalUrl,
    String? syncState,
    String? remoteTargetName,
  }) {
    return ShootingRecord(
      id: id ?? this.id,
      celestialObjectId: celestialObjectId ?? this.celestialObjectId,
      capturedAt: capturedAt ?? this.capturedAt,
      photoUri: photoUri ?? this.photoUri,
      originalFilename: originalFilename ?? this.originalFilename,
      memo: memo ?? this.memo,
      location: clearLocation ? null : (location ?? this.location),
      exif: exif ?? this.exif,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      isRepresentative: isRepresentative ?? this.isRepresentative,
      isFavorite: isFavorite ?? this.isFavorite,
      plateSolve: clearPlateSolve ? null : (plateSolve ?? this.plateSolve),
      detectMethod: detectMethod ?? this.detectMethod,
      analysisStatus: analysisStatus ?? this.analysisStatus,
      backendRecordId: backendRecordId ?? this.backendRecordId,
      backendRevision: backendRevision ?? this.backendRevision,
      backendFileId: backendFileId ?? this.backendFileId,
      commonFileId: commonFileId ?? this.commonFileId,
      plateSolveQueueStatus:
          plateSolveQueueStatus ?? this.plateSolveQueueStatus,
      plateSolveJobId: plateSolveJobId ?? this.plateSolveJobId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      originalUrl: originalUrl ?? this.originalUrl,
      syncState: syncState ?? this.syncState,
      remoteTargetName: remoteTargetName ?? this.remoteTargetName,
    );
  }
}
