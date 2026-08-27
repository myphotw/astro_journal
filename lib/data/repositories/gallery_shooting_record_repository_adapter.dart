import 'dart:async';

import '../../services/catalog_search_service.dart';
import '../../services/catalog_capture_projection_service.dart';
import '../../services/app_logger.dart';
import '../../services/tc_backend_sync_coordinator.dart';
import '../datasources/gallery_record_link_datasource.dart';
import '../models/catalog_object.dart';
import '../models/gallery_item.dart';
import '../models/gallery_observation_projection.dart';
import '../models/shooting_record.dart';
import 'catalog_repository.dart';
import 'gallery_repository.dart';
import 'shooting_record_repository.dart';
import 'sync_outbox_repository.dart';

class GalleryObservationProjectionMapper {
  GalleryObservationProjectionMapper(this._catalogSearchService);

  final CatalogSearchService _catalogSearchService;

  GalleryObservationProjection toProjection(
    GalleryItem item, {
    required List<CatalogObject> catalog,
  }) {
    CatalogObject? resolved;
    for (final object in catalog) {
      if (object.id.toLowerCase() == item.catalogObjectId.toLowerCase()) {
        resolved = object;
        break;
      }
    }
    resolved ??= _catalogSearchService.resolveTarget(
      item.catalogObjectId,
      catalog,
    );
    return GalleryObservationProjection.fromGalleryItem(
      item,
      resolvedTargetName: resolved?.displayCommonName,
    );
  }
}

/// Adapts canonical Astro Gallery records to the V1 GalleryViewModel contract.
/// Local and remote records are merged only through the durable
/// backend_record_id -> local_record_id outbox link. Filename/date guessing is
/// intentionally not used.
class GalleryShootingRecordRepositoryAdapter
    implements ShootingRecordRepository {
  factory GalleryShootingRecordRepositoryAdapter({
    required GalleryRepository galleryRepository,
    required ShootingRecordRepository localRepository,
    required CatalogRepository catalogRepository,
    required GalleryObservationProjectionMapper projectionMapper,
    GalleryRecordLinkDataSource linkDataSource =
        const EmptyGalleryRecordLinkDataSource(),
    SyncOutboxRepository? syncOutboxRepository,
    TcBackendDrainRunner? syncCoordinator,
    CatalogCaptureProjectionService? catalogCaptureProjection,
    void Function()? onRecordsChanged,
  }) => GalleryShootingRecordRepositoryAdapter._(
    galleryRepository,
    localRepository,
    catalogRepository,
    projectionMapper,
    linkDataSource,
    syncOutboxRepository,
    syncCoordinator,
    catalogCaptureProjection,
    onRecordsChanged,
  );

  GalleryShootingRecordRepositoryAdapter._(
    this._galleryRepository,
    this._localRepository,
    this._catalogRepository,
    this._projectionMapper,
    this._linkDataSource,
    this._syncOutboxRepository,
    this._syncCoordinator,
    this._catalogCaptureProjection,
    this._onRecordsChanged,
  );

  final GalleryRepository _galleryRepository;
  final ShootingRecordRepository _localRepository;
  final CatalogRepository _catalogRepository;
  final GalleryObservationProjectionMapper _projectionMapper;
  final GalleryRecordLinkDataSource _linkDataSource;
  final SyncOutboxRepository? _syncOutboxRepository;
  final TcBackendDrainRunner? _syncCoordinator;
  final CatalogCaptureProjectionService? _catalogCaptureProjection;
  final void Function()? _onRecordsChanged;
  Map<String, ShootingRecord> _lastRemoteRecords = const {};

  @override
  Future<List<ShootingRecord>> getAll() async {
    final local = await _localRepository.getAll();
    final snapshot = await _galleryRepository.getSnapshot();
    if (snapshot.source == GallerySnapshotSource.none ||
        (snapshot.source == GallerySnapshotSource.cache &&
            snapshot.items.isEmpty)) {
      _lastRemoteRecords = const {};
      return local;
    }

    final catalog = await _catalogRepository.getAll(listOnly: true);
    final links = await _linkDataSource.localIdsByBackendRecordId();
    final localById = {for (final record in local) record.id: record};
    final matchedLocalIds = <String>{};
    final projected = <ShootingRecord>[];

    for (final item in snapshot.items) {
      final remoteProjectionId = 'remote:${item.backendRecordId}';
      final linkedLocalId =
          links[item.backendRecordId] ??
          (localById.containsKey(remoteProjectionId)
              ? remoteProjectionId
              : null);
      final localRecord = linkedLocalId == null
          ? null
          : localById[linkedLocalId];
      if (localRecord != null) matchedLocalIds.add(localRecord.id);
      projected.add(
        _projectionMapper
            .toProjection(item, catalog: catalog)
            .toShootingRecord(localRecord: localRecord),
      );
    }

    // Pending/V1 local-only records remain visible next to canonical remote rows.
    projected.addAll(
      local.where((record) => !matchedLocalIds.contains(record.id)),
    );
    _lastRemoteRecords = {
      for (final record in projected)
        if (record.backendRecordId != null) record.id: record,
    };
    return projected;
  }

  bool _isRemoteOnly(String id) =>
      id.startsWith('remote:') && _lastRemoteRecords.containsKey(id);

  @override
  Future<ShootingRecord?> getById(String id) async {
    final current = _lastRemoteRecords[id];
    final backendRecordId = current?.backendRecordId;
    if (current != null && backendRecordId != null) {
      final item = await _galleryRepository.getById(backendRecordId);
      if (item == null) return current;
      final catalog = await _catalogRepository.getAll(listOnly: true);
      final localRecord = await _localRepository.getById(id);
      final detailed = _projectionMapper
          .toProjection(item, catalog: catalog)
          .toShootingRecord(localRecord: localRecord);
      _lastRemoteRecords = {..._lastRemoteRecords, detailed.id: detailed};
      return detailed;
    }
    return _localRepository.getById(id);
  }

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async =>
      (await getAll())
          .where((record) => record.celestialObjectId == id)
          .toList();

  @override
  Future<ShootingRecord?> findByOriginalFilename(String filename) async {
    for (final record in await getAll()) {
      if (record.originalFilename == filename) return record;
    }
    return null;
  }

  @override
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) async {
    for (final record in await getAll()) {
      if (record.celestialObjectId == celestialObjectId &&
          record.capturedAt.difference(capturedAt).abs() <= tolerance) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> save(ShootingRecord record) async {
    await _localRepository.save(record);
    _onRecordsChanged?.call();
  }

  @override
  Future<void> update(ShootingRecord record) async {
    final previous = _lastRemoteRecords[record.id];
    if (_isRemoteOnly(record.id)) {
      // Remote canonical rows still need a durable local projection for fields
      // not yet present in the ObservationRecord API (integration/equipment).
      // ShootingRecord.toMap intentionally omits transient backend identifiers.
      await _localRepository.save(record);
    } else {
      await _localRepository.update(record);
    }
    _lastRemoteRecords = {..._lastRemoteRecords, record.id: record};
    if (previous == null || previous.backendRecordId == null) {
      _onRecordsChanged?.call();
      return;
    }

    final fields = <String, Object?>{};
    if (previous.isFavorite != record.isFavorite) {
      fields['favorite'] = record.isFavorite;
    }
    if (previous.memo != record.memo) fields['memo'] = record.memo;
    if (previous.isRepresentative != record.isRepresentative) {
      fields['representative'] = record.isRepresentative;
    }
    final previousLocation = previous.exif?.locationName ?? previous.location;
    final nextLocation = record.exif?.locationName ?? record.location;
    if (previousLocation != nextLocation) {
      fields['location_name'] = nextLocation;
    }
    if (previous.exif?.lat != record.exif?.lat) {
      fields['latitude'] = record.exif?.lat;
    }
    if (previous.exif?.lng != record.exif?.lng) {
      fields['longitude'] = record.exif?.lng;
    }
    await _queuePatch(record, fields);
    _onRecordsChanged?.call();
  }

  @override
  Future<void> delete(String id) async {
    final record = _lastRemoteRecords[id];
    if (record?.backendRecordId == null) {
      final local = await _localRepository.getById(id);
      await _localRepository.delete(id);
      await _syncOutboxRepository?.cancelPendingUpload(id);
      await _reconcileCatalog(local?.celestialObjectId);
      _onRecordsChanged?.call();
      return;
    }
    final remoteOnly = _isRemoteOnly(id);
    if (!remoteOnly || await _localRepository.getById(id) != null) {
      await _localRepository.delete(id);
    }
    await _galleryRepository.applyLocalDelete(record!.backendRecordId!);
    final updated = Map<String, ShootingRecord>.from(_lastRemoteRecords)
      ..remove(id);
    _lastRemoteRecords = updated;
    await _syncOutboxRepository?.enqueueRecordDelete(
      backendRecordId: record.backendRecordId!,
      localRecordId: remoteOnly ? null : id,
    );
    await _reconcileCatalog(record.celestialObjectId);
    _onRecordsChanged?.call();
    _requestDrain();
  }

  Future<void> _reconcileCatalog(String? catalogObjectId) async {
    final projection = _catalogCaptureProjection;
    if (projection == null || catalogObjectId == null) return;
    try {
      await projection.reconcileObject(catalogObjectId);
    } catch (error, stackTrace) {
      AppLogger.error('GalleryDelete.CatalogProjection', error, stackTrace);
    }
  }

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) =>
      _localRepository.clearRepresentativeForObject(celestialObjectId);

  @override
  Future<void> setRepresentative(String recordId) async {
    final record = _lastRemoteRecords[recordId];
    if (record?.backendRecordId == null) {
      await _localRepository.setRepresentative(recordId);
      return;
    }
    final remoteOnly = _isRemoteOnly(recordId);
    if (!remoteOnly) await _localRepository.setRepresentative(recordId);
    await _galleryRepository.applyLocalPatch(record!.backendRecordId!, const {
      'representative': true,
    });
    _lastRemoteRecords = {
      for (final entry in _lastRemoteRecords.entries)
        entry.key: entry.value.celestialObjectId == record.celestialObjectId
            ? entry.value.copyWith(isRepresentative: entry.key == recordId)
            : entry.value,
    };
    final revision = record.backendRevision;
    if (revision != null) {
      await _syncOutboxRepository?.enqueueRecordPatch(
        backendRecordId: record.backendRecordId!,
        expectedRevision: revision,
        fields: const {'representative': true},
        localRecordId: remoteOnly ? null : recordId,
      );
      _requestDrain();
    }
  }

  Future<void> _queuePatch(
    ShootingRecord record,
    Map<String, Object?> fields,
  ) async {
    if (fields.isEmpty ||
        record.backendRecordId == null ||
        record.backendRevision == null) {
      return;
    }
    await _galleryRepository.applyLocalPatch(record.backendRecordId!, fields);
    await _syncOutboxRepository?.enqueueRecordPatch(
      backendRecordId: record.backendRecordId!,
      expectedRevision: record.backendRevision!,
      fields: fields,
      localRecordId: _isRemoteOnly(record.id) ? null : record.id,
    );
    _requestDrain();
  }

  void _requestDrain() {
    final coordinator = _syncCoordinator;
    if (coordinator == null) return;
    unawaited(
      coordinator.drain().catchError((Object error, StackTrace stack) {
        AppLogger.error('GalleryMutationSync', error, stack);
      }),
    );
  }
}
