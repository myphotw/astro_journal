import '../../core/constants/analysis_status.dart';
import 'gallery_item.dart';
import 'shooting_record.dart';

class GalleryObservationProjection {
  const GalleryObservationProjection({
    required this.backendFileId,
    required this.captureDatetime,
    required this.favorite,
    required this.syncState,
    this.thumbnailUrl,
    this.previewUrl,
    this.originalUrl,
    this.location,
    this.targetName,
    this.catalogObjectId,
    this.originalFilename,
    this.localRecordId,
  });

  final String backendFileId;
  final String? thumbnailUrl;
  final String? previewUrl;
  final String? originalUrl;
  final DateTime captureDatetime;
  final bool favorite;
  final String? location;
  final String? targetName;
  final String? catalogObjectId;
  final String syncState;
  final String? originalFilename;
  final String? localRecordId;

  factory GalleryObservationProjection.fromGalleryItem(
    GalleryItem item, {
    required DateTime fallbackTime,
  }) => GalleryObservationProjection(
    backendFileId: item.backendFileId,
    thumbnailUrl: item.thumbnailUrl,
    previewUrl: item.previewUrl,
    originalUrl: item.originalUrl,
    captureDatetime: item.capturedAt ?? item.syncedAt ?? fallbackTime,
    favorite: item.favorite,
    location: item.location,
    targetName: item.targetName,
    catalogObjectId: item.catalogObjectId,
    syncState: item.syncState ?? 'SYNCED',
    originalFilename: item.originalFilename,
    localRecordId: item.metadata['local_record_id']?.toString(),
  );

  ShootingRecord toShootingRecord({
    ShootingRecord? localRecord,
    String? resolvedCatalogObjectId,
  }) {
    final localPhoto = localRecord?.photoUri;
    return ShootingRecord(
      id: localRecord?.id ?? 'remote:$backendFileId',
      celestialObjectId: localRecord?.celestialObjectId ??
          resolvedCatalogObjectId ??
          catalogObjectId ??
          targetName ??
          'remote:$backendFileId',
      capturedAt: localRecord?.capturedAt ?? captureDatetime,
      photoUri: localPhoto ?? previewUrl ?? thumbnailUrl ?? originalUrl,
      originalFilename: localRecord?.originalFilename ?? originalFilename,
      memo: localRecord?.memo ?? '',
      location: localRecord?.location ?? location,
      exif: localRecord?.exif,
      metadataJson: localRecord?.metadataJson,
      createdAt: localRecord?.createdAt ?? captureDatetime,
      isRepresentative: localRecord?.isRepresentative ?? false,
      isFavorite: localRecord?.isFavorite ?? favorite,
      plateSolve: localRecord?.plateSolve,
      detectMethod: localRecord?.detectMethod,
      analysisStatus: localRecord?.analysisStatus ?? AnalysisStatus.completed,
      backendFileId: backendFileId,
      thumbnailUrl: thumbnailUrl,
      previewUrl: previewUrl,
      originalUrl: originalUrl,
      syncState: syncState,
      remoteTargetName: targetName,
    );
  }
}
