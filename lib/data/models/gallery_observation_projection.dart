import '../../core/constants/analysis_status.dart';
import 'exif_info.dart';
import 'gallery_item.dart';
import 'shooting_record.dart';

class GalleryObservationProjection {
  const GalleryObservationProjection({
    required this.backendRecordId,
    required this.revision,
    required this.backendFileId,
    required this.catalogObjectId,
    required this.captureDatetime,
    required this.favorite,
    required this.representative,
    required this.memo,
    required this.syncState,
    required this.thumbnailUrl,
    required this.previewUrl,
    required this.originalUrl,
    this.location,
    this.latitude,
    this.longitude,
    this.targetName,
    this.originalFilename,
    this.mimeType,
  });

  final String backendRecordId;
  final int revision;
  final String backendFileId;
  final String catalogObjectId;
  final String thumbnailUrl;
  final String previewUrl;
  final String originalUrl;
  final DateTime captureDatetime;
  final bool favorite;
  final bool representative;
  final String memo;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? targetName;
  final String syncState;
  final String? originalFilename;
  final String? mimeType;

  factory GalleryObservationProjection.fromGalleryItem(
    GalleryItem item, {
    String? resolvedTargetName,
  }) => GalleryObservationProjection(
    backendRecordId: item.backendRecordId,
    revision: item.revision,
    backendFileId: item.backendFileId,
    catalogObjectId: item.catalogObjectId,
    thumbnailUrl: item.thumbnailUrl,
    previewUrl: item.previewUrl,
    originalUrl: item.originalUrl,
    captureDatetime: item.capturedAt,
    favorite: item.favorite,
    representative: item.representative,
    memo: item.memo,
    location: item.location,
    latitude: item.latitude,
    longitude: item.longitude,
    targetName: resolvedTargetName ??
        item.catalogObjectId.ifNotEmpty ??
        item.originalFilename,
    syncState: item.syncState ?? 'SYNCED',
    originalFilename: item.originalFilename,
    mimeType: item.mimeType,
  );

  ShootingRecord toShootingRecord({ShootingRecord? localRecord}) {
    final filename = originalFilename ?? localRecord?.originalFilename ?? '';
    final baseExif =
        localRecord?.exif ?? ExifInfo.placeholder(filename: filename);
    final projectedExif = ExifInfo(
      filename: baseExif.filename.isEmpty ? filename : baseExif.filename,
      originalFilename: filename.ifNotEmpty,
      size: baseExif.size,
      date: captureDatetime.toIso8601String(),
      targetName: targetName,
      equipment: baseExif.equipment,
      focal: baseExif.focal,
      fstop: baseExif.fstop,
      exposure: baseExif.exposure,
      iso: baseExif.iso,
      resolution: baseExif.resolution,
      lat: latitude,
      lng: longitude,
      locationName: location,
      address: baseExif.address,
      stackNum: baseExif.stackNum,
      singleExpSec: baseExif.singleExpSec,
      filter: baseExif.filter,
      imageWidth: baseExif.imageWidth,
      imageHeight: baseExif.imageHeight,
      ownerNameJson: baseExif.ownerNameJson,
      makerNoteJson: baseExif.makerNoteJson,
      ra: baseExif.ra,
      dec: baseExif.dec,
    );
    return ShootingRecord(
      id: localRecord?.id ?? 'remote:$backendRecordId',
      celestialObjectId: catalogObjectId,
      capturedAt: captureDatetime,
      photoUri: localRecord?.photoUri ?? previewUrl,
      originalFilename: filename.ifNotEmpty,
      memo: memo,
      location: location,
      exif: projectedExif,
      metadataJson: localRecord?.metadataJson,
      createdAt: localRecord?.createdAt ?? captureDatetime,
      isRepresentative: representative,
      isFavorite: favorite,
      plateSolve: localRecord?.plateSolve,
      detectMethod: localRecord?.detectMethod,
      analysisStatus: localRecord?.analysisStatus ?? AnalysisStatus.completed,
      backendRecordId: backendRecordId,
      backendRevision: revision,
      backendFileId: backendFileId,
      thumbnailUrl: thumbnailUrl,
      previewUrl: previewUrl,
      originalUrl: originalUrl,
      syncState: syncState,
      remoteTargetName: targetName,
    );
  }
}

extension on String {
  String? get ifNotEmpty => trim().isEmpty ? null : this;
}
