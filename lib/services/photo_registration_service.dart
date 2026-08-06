import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';



import '../features/photo_first/widgets/photo_gallery_picker_screen.dart';
import '../core/constants/analysis_status.dart';

import '../core/constants/detect_method.dart';

import '../data/models/exif_info.dart';

import '../data/models/photo_metadata.dart';

import '../data/models/plate_solve_result.dart';

import '../data/models/seestar_metadata.dart';

import '../data/models/shooting_record.dart';

import '../data/repositories/catalog_repository.dart';

import '../data/repositories/shooting_record_repository.dart';

import 'api_key_service.dart';

import 'app_logger.dart';

import 'geocoding_service.dart';

import 'exif_service.dart';

import 'metadata_format.dart';

import 'metadata_field_trace.dart';

import 'photo_metadata_pipeline.dart';

import 'photo_service.dart';



/// 사진 등록 파이프라인 전체를 담당하는 서비스.

class PhotoRegistrationService {

  PhotoRegistrationService({

    required this.photoService,

    required this.geocodingService,

    required this.apiKeyService,

    required this.exifService,

    required this.shootingRecordRepository,

    required this.catalogRepository,

    PhotoMetadataPipeline? metadataPipeline,

  }) : _metadataPipeline = metadataPipeline ??

            PhotoMetadataPipeline(exifService: exifService);



  final PhotoService photoService;

  final GeocodingService geocodingService;

  final ApiKeyService apiKeyService;

  final ExifService exifService;

  final ShootingRecordRepository shootingRecordRepository;

  final CatalogRepository catalogRepository;

  final PhotoMetadataPipeline _metadataPipeline;



  static const _uuid = Uuid();



  Future<PhotoRegistrationPayload?> pickAndPrepare() async {

    AppLogger.metadata('PhotoRegistration', '사진 선택 시작');



    final picked = await photoService.pickAndCopyOnly();

    if (picked == null) {

      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');

      return null;

    }



    return _prepareFromPick(picked);

  }



  /// 갤러리 화면에서 여러 장 선택 후 파일만 복사한다 (EXIF는 이후 [enrichPayload]).
  Future<List<PhotoRegistrationPayload>> pickMultipleAndCopyOnly(
    BuildContext context,
  ) async {
    AppLogger.metadata('PhotoRegistration', '다중 사진 복사(EXIF 지연) 시작');

    final files = await PhotoGalleryPicker.pick(context);
    if (files.isEmpty) {
      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');
      return [];
    }

    final picked = await photoService.copyPickedFilesWithoutExif(files);
    if (picked.isEmpty) {
      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');
      return [];
    }

    return [
      for (final item in picked)
        PhotoRegistrationPayload(
          photoId: item.id,
          localPath: item.localPath,
          originalFilename: item.originalFilename,
          exifInfo: item.exifInfo,
          metadata: const PhotoMetadata(),
        ),
    ];
  }

  /// 갤러리 화면에서 여러 장 선택 후 각각 메타데이터 파이프라인을 실행한다.
  Future<List<PhotoRegistrationPayload>> pickMultipleAndPrepare(
    BuildContext context,
  ) async {
    AppLogger.metadata('PhotoRegistration', '다중 사진 선택 시작');

    final files = await PhotoGalleryPicker.pick(context);
    if (files.isEmpty) {
      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');
      return [];
    }

    final picked = await photoService.copyPickedFiles(files);

    if (picked.isEmpty) {
      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');
      return [];
    }

    final payloads = <PhotoRegistrationPayload>[];

    for (final item in picked) {
      payloads.add(await _prepareFromPick(item));
      // EXIF/파이프라인 사이 프레임 양보 → 로딩 UI 끊김 완화
      await Future<void>.delayed(Duration.zero);
    }

    return payloads;
  }

  /// 복사만 된 stub payload에 EXIF + 메타데이터 파이프라인을 적용한다.
  Future<PhotoRegistrationPayload> enrichPayload(
    PhotoRegistrationPayload stub,
  ) async {
    final exif = await exifService.extractFromPath(
      stub.localPath,
      originalFilename: stub.originalFilename,
    );
    final processed = await _metadataPipeline.process(
      exif: exif,
      originalFilename: stub.originalFilename,
      imagePath: stub.localPath,
    );
    MetadataFieldTrace.logExifInfo('Registration.Enrich', processed.exifInfo);
    return stub.copyWith(
      exifInfo: processed.exifInfo,
      makerNoteMetadata: processed.makerNoteMetadata,
      ownerNameMetadata: processed.ownerNameMetadata,
      filenameMetadata: processed.filenameMetadata,
      metadata: processed.metadata,
    );
  }

  /// 단일 사진: 복사만 (EXIF 지연).
  Future<PhotoRegistrationPayload?> pickAndCopyOnly() async {
    AppLogger.metadata('PhotoRegistration', '사진 복사(EXIF 지연) 시작');
    final picked = await photoService.pickAndCopyOnly(extractExif: false);
    if (picked == null) {
      AppLogger.metadata('PhotoRegistration', '사용자가 사진 선택 취소');
      return null;
    }
    return PhotoRegistrationPayload(
      photoId: picked.id,
      localPath: picked.localPath,
      originalFilename: picked.originalFilename,
      exifInfo: picked.exifInfo,
      metadata: const PhotoMetadata(),
    );
  }

  Future<PhotoRegistrationPayload> _prepareFromPick(PhotoPickResult picked) async {

    AppLogger.metadata(

      'PhotoRegistration',

      '사진 복사 완료: ${picked.originalFilename} → ${p.basename(picked.localPath)}',

    );



    final processed = await _metadataPipeline.process(

      exif: picked.exifInfo,

      originalFilename: picked.originalFilename,

      imagePath: picked.localPath,

    );

    MetadataFieldTrace.logExifInfo('Registration.Payload', processed.exifInfo);



    return PhotoRegistrationPayload(

      photoId: picked.id,

      localPath: picked.localPath,

      originalFilename: picked.originalFilename,

      exifInfo: processed.exifInfo,

      makerNoteMetadata: processed.makerNoteMetadata,

      ownerNameMetadata: processed.ownerNameMetadata,

      filenameMetadata: processed.filenameMetadata,

      metadata: processed.metadata,

    );

  }



  /// 동일 원본 파일명 중복 여부만 확인한다 (사진 선택 직후용).
  Future<DuplicateCheckResult?> checkDuplicateByFilename(
    PhotoRegistrationPayload payload,
  ) async {
    final byFilename = await shootingRecordRepository.findByOriginalFilename(
      payload.originalFilename,
    );
    if (byFilename == null) return null;
    return DuplicateCheckResult(
      reason: DuplicateReason.sameFilename,
      existing: byFilename,
    );
  }

  /// 동일 파일명 또는 동일 촬영 기록 중복 여부를 확인한다.

  Future<DuplicateCheckResult?> checkDuplicate({

    required PhotoRegistrationPayload payload,

    required String celestialObjectId,

    ConfirmedMetadata? confirmed,

  }) async {

    final byFilename = await checkDuplicateByFilename(payload);

    if (byFilename != null) {

      return byFilename;

    }



    final capturedAt = _resolveCapturedAt(payload, confirmed);

    final byCapture = await shootingRecordRepository.findByObjectAndCapturedAt(

      celestialObjectId,

      capturedAt,

    );

    if (byCapture != null) {

      return DuplicateCheckResult(

        reason: DuplicateReason.sameCapture,

        existing: byCapture,

      );

    }

    return null;

  }



  /// 사진 파일 저장, ShootingRecord 저장, 카탈로그 captured 갱신.
  Future<ShootingRecord> registerPhotoRecord({
    required PhotoRegistrationPayload payload,
    required ConfirmedMetadata confirmed,
    required String celestialObjectId,
    DetectMethod? detectMethod,
    AnalysisStatus analysisStatus = AnalysisStatus.completed,
    PlateSolveResult? plateSolve,
  }) async {
    await savePhotoFile(payload);
    // 파일 I/O 후 UI 프레임 양보
    await Future<void>.delayed(Duration.zero);

    final saveData = await buildSaveData(
      payload: payload,
      confirmed: confirmed,
      celestialObjectId: celestialObjectId,
      detectMethod: detectMethod,
      analysisStatus: analysisStatus,
      plateSolve: plateSolve,
    );

    final existingRecords =
        await shootingRecordRepository.getByCelestialObjectId(
      celestialObjectId,
    );

    final hasRepresentative = existingRecords.any(
      (r) =>
          r.isRepresentative &&
          r.photoUri != null &&
          r.photoUri!.isNotEmpty,
    );

    final shouldBeRepresentative =
        !hasRepresentative && payload.localPath.isNotEmpty;

    final record = saveData.toRecord(
      isRepresentative: shouldBeRepresentative,
    );

    await shootingRecordRepository.save(record);
    AppLogger.metadata('PhotoRegistration', 'ShootingRecord 저장 완료');
    await Future<void>.delayed(Duration.zero);

    final capturedAt = saveData.capturedAt;
    final dateStr =
        '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')}';

    await catalogRepository.updateCaptured(
      celestialObjectId,
      captured: true,
      capturedDate: dateStr,
    );
    AppLogger.metadata('PhotoRegistration', 'Catalog captured 갱신 완료');
    return record;
  }



  DateTime _resolveCapturedAt(

    PhotoRegistrationPayload payload,

    ConfirmedMetadata? confirmed,

  ) {

    final now = DateTime.now();

    final capturedAtStr = confirmed?.capturedAt;

    if (capturedAtStr != null && capturedAtStr.isNotEmpty) {

      return DateTime.tryParse(capturedAtStr) ?? now;

    }

    if (payload.exifInfo.date.isNotEmpty) {

      return DateTime.tryParse(payload.exifInfo.date) ?? now;

    }

    return now;

  }



  Future<PhotoSaveData> buildSaveData({

    required PhotoRegistrationPayload payload,

    required ConfirmedMetadata confirmed,

    required String celestialObjectId,

    DetectMethod? detectMethod,

    AnalysisStatus analysisStatus = AnalysisStatus.completed,

    PlateSolveResult? plateSolve,

  }) async {

    AppLogger.metadata('PhotoRegistration', '저장 데이터 생성 시작');

    _logFinalMetadata(payload, confirmed);



    final now = DateTime.now();



    DateTime capturedAt;

    final capturedAtStr = confirmed.capturedAt;

    if (capturedAtStr != null && capturedAtStr.isNotEmpty) {

      capturedAt = DateTime.tryParse(capturedAtStr) ?? now;

    } else if (payload.exifInfo.date.isNotEmpty) {

      capturedAt = DateTime.tryParse(payload.exifInfo.date) ?? now;

    } else {

      capturedAt = now;

    }



    final double? finalLat = confirmed.lat ?? payload.exifInfo.lat;

    final double? finalLng = confirmed.lng ?? payload.exifInfo.lng;



    String? locationName = confirmed.locationName;

    String? address;

    if (finalLat != null && finalLng != null) {

      try {

        final mapsKey = await apiKeyService.get(ApiKeyType.googleMaps) ?? '';

        final geoResult = await geocodingService.getLocationInfo(

          finalLat,

          finalLng,

          mapsKey,

        );

        if (geoResult != null) {

          locationName ??= geoResult.locationName;

          address = geoResult.address;

        }

      } catch (e) {

        AppLogger.metadata('PhotoRegistration', 'Geocoding 실패: $e');

        AppLogger.error('PhotoRegistration.geocoding', e);

      }

    }



    final updatedExif = payload.exifInfo.copyWith(

      targetName: confirmed.targetName?.isNotEmpty == true

          ? confirmed.targetName

          : payload.exifInfo.targetName,

      equipment: confirmed.equipment?.isNotEmpty == true

          ? confirmed.equipment!

          : payload.exifInfo.equipment,

      date: confirmed.capturedAt?.isNotEmpty == true

          ? confirmed.capturedAt!

          : payload.exifInfo.date,

      exposure: confirmed.totalExpSec?.isNotEmpty == true

          ? confirmed.totalExpSec!

          : payload.exifInfo.exposure,

      lat: finalLat,

      lng: finalLng,

      locationName: locationName,

      address: address,

      stackNum: confirmed.stackNum ?? payload.exifInfo.stackNum,

      singleExpSec: confirmed.singleExpSec?.isNotEmpty == true

          ? confirmed.singleExpSec

          : payload.exifInfo.singleExpSec,

      filter: confirmed.filter?.isNotEmpty == true

          ? confirmed.filter

          : payload.exifInfo.filter,

      iso: confirmed.iso?.isNotEmpty == true

          ? confirmed.iso!

          : payload.exifInfo.iso,

      fstop: confirmed.fstop?.isNotEmpty == true

          ? confirmed.fstop!

          : payload.exifInfo.fstop,

      focal: confirmed.focal?.isNotEmpty == true

          ? confirmed.focal!

          : payload.exifInfo.focal,

    );

    MetadataFieldTrace.logExifInfo('Registration.Save', updatedExif);



    return PhotoSaveData(

      recordId: _uuid.v4(),

      photoId: payload.photoId,

      localPath: payload.localPath,

      originalFilename: payload.originalFilename,

      celestialObjectId: celestialObjectId,

      capturedAt: capturedAt,

      updatedExif: updatedExif,

      locationName: locationName,

      metadataJson: payload.exifInfo.makerNoteJson ??

          payload.exifInfo.ownerNameJson,

      createdAt: now,

      memo: confirmed.memo ?? '',

      detectMethod: detectMethod,

      analysisStatus: analysisStatus,

      plateSolve: plateSolve,

    );

  }



  void _logFinalMetadata(

    PhotoRegistrationPayload payload,

    ConfirmedMetadata confirmed,

  ) {

    final exif = payload.exifInfo;

    AppLogger.metadata('PhotoRegistration', '=== 저장 직전 최종 메타데이터 ===');

    AppLogger.metadata(

      'PhotoRegistration',

      'Target : ${exif.targetName ?? "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'Date : ${MetadataFormat.formatDateTimeInput(exif.date.isNotEmpty ? exif.date : null).isNotEmpty ? MetadataFormat.formatDateTimeInput(exif.date) : "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'Creator : ${exif.equipment.isNotEmpty ? exif.equipment : "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'Latitude : ${exif.lat?.toStringAsFixed(6) ?? "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'Longitude : ${exif.lng?.toStringAsFixed(6) ?? "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'StackNum : ${exif.stackNum ?? "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'ExpSec : ${exif.singleExpSec ?? "-"}',

    );

    AppLogger.metadata(

      'PhotoRegistration',

      'TotExpSec : ${exif.exposure.isNotEmpty ? exif.exposure : "-"}',

    );

    if (confirmed.targetName != null && confirmed.targetName!.isNotEmpty) {

      AppLogger.metadata(

        'PhotoRegistration',

        'ConfirmedTarget : ${confirmed.targetName}',

      );

    }

    AppLogger.metadata('PhotoRegistration', '=== END ===');

  }



  Future<void> savePhotoFile(PhotoRegistrationPayload payload) async {

    await photoService.savePickResult(

      PhotoPickResult(

        id: payload.photoId,

        localPath: payload.localPath,

        originalFilename: payload.originalFilename,

        exifInfo: payload.exifInfo,

      ),

    );

  }

}



class PhotoRegistrationPayload {

  const PhotoRegistrationPayload({

    required this.photoId,

    required this.localPath,

    required this.originalFilename,

    required this.exifInfo,

    this.makerNoteMetadata,

    this.ownerNameMetadata,

    this.filenameMetadata,

    required this.metadata,

  });



  final String photoId;

  final String localPath;

  final String originalFilename;



  /// 파이프라인 병합이 반영된 ExifInfo.

  final ExifInfo exifInfo;

  final SeestarMetadata? makerNoteMetadata;

  final SeestarMetadata? ownerNameMetadata;

  final SeestarMetadata? filenameMetadata;

  final PhotoMetadata metadata;

  PhotoRegistrationPayload copyWith({
    String? photoId,
    String? localPath,
    String? originalFilename,
    ExifInfo? exifInfo,
    SeestarMetadata? makerNoteMetadata,
    SeestarMetadata? ownerNameMetadata,
    SeestarMetadata? filenameMetadata,
    PhotoMetadata? metadata,
  }) {
    return PhotoRegistrationPayload(
      photoId: photoId ?? this.photoId,
      localPath: localPath ?? this.localPath,
      originalFilename: originalFilename ?? this.originalFilename,
      exifInfo: exifInfo ?? this.exifInfo,
      makerNoteMetadata: makerNoteMetadata ?? this.makerNoteMetadata,
      ownerNameMetadata: ownerNameMetadata ?? this.ownerNameMetadata,
      filenameMetadata: filenameMetadata ?? this.filenameMetadata,
      metadata: metadata ?? this.metadata,
    );
  }

}



class ConfirmedMetadata {

  const ConfirmedMetadata({

    this.targetName,

    this.memo,

    this.capturedAt,

    this.equipment,

    this.locationName,

    this.lat,

    this.lng,

    this.stackNum,

    this.singleExpSec,

    this.totalExpSec,

    this.filter,

    this.iso,

    this.fstop,

    this.focal,

  });



  final String? targetName;

  final String? memo;

  final String? capturedAt;

  final String? equipment;

  final String? locationName;

  final double? lat;

  final double? lng;

  final int? stackNum;

  final String? singleExpSec;

  final String? totalExpSec;

  final String? filter;

  final String? iso;

  final String? fstop;

  final String? focal;



  /// EXIF 분석 결과로 기본 등록 정보를 생성한다.

  factory ConfirmedMetadata.fromExif(

    ExifInfo exif, {

    String? targetName,

  }) {

    String? parseIso(String? raw) {

      if (raw == null || raw.isEmpty) return null;

      final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));

      return dt?.toIso8601String() ?? raw;

    }



    return ConfirmedMetadata(

      targetName: targetName ?? exif.targetName,

      capturedAt: parseIso(

        exif.date.isNotEmpty

            ? MetadataFormat.formatDateTimeInput(exif.date)

            : null,

      ),

      equipment: exif.equipment.isNotEmpty ? exif.equipment : null,

      lat: exif.lat,

      lng: exif.lng,

      locationName: exif.locationName,

      stackNum: exif.stackNum,

      singleExpSec: exif.singleExpSec,

      totalExpSec: exif.exposure.isNotEmpty ? exif.exposure : null,

      filter: exif.filter,

      iso: exif.iso.isNotEmpty ? exif.iso : null,

      fstop: exif.fstop.isNotEmpty ? exif.fstop : null,

      focal: exif.focal.isNotEmpty ? exif.focal : null,

    );

  }

}



enum DuplicateReason {

  sameFilename,

  sameCapture,

}



class DuplicateCheckResult {

  const DuplicateCheckResult({

    required this.reason,

    required this.existing,

  });



  final DuplicateReason reason;

  final ShootingRecord existing;

}



class PhotoSaveData {

  const PhotoSaveData({

    required this.recordId,

    required this.photoId,

    required this.localPath,

    required this.originalFilename,

    required this.celestialObjectId,

    required this.capturedAt,

    required this.updatedExif,

    this.locationName,

    this.metadataJson,

    required this.createdAt,

    this.memo = '',

    this.detectMethod,

    this.analysisStatus = AnalysisStatus.completed,

    this.plateSolve,

  });



  final String recordId;

  final String photoId;

  final String localPath;

  final String originalFilename;

  final String celestialObjectId;

  final DateTime capturedAt;

  final ExifInfo updatedExif;

  final String? locationName;

  final String? metadataJson;

  final DateTime createdAt;

  final String memo;

  final DetectMethod? detectMethod;

  final AnalysisStatus analysisStatus;

  final PlateSolveResult? plateSolve;



  ShootingRecord toRecord({bool isRepresentative = false}) {

    return ShootingRecord(

      id: recordId,

      celestialObjectId: celestialObjectId,

      capturedAt: capturedAt,

      photoUri: localPath,

      originalFilename: originalFilename,

      memo: memo,

      location: locationName,

      exif: updatedExif,

      metadataJson: metadataJson,

      createdAt: createdAt,

      isRepresentative: isRepresentative,

      detectMethod: detectMethod,

      analysisStatus: analysisStatus,

      plateSolve: plateSolve,

    );

  }

}


