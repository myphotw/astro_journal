import '../../services/catalog_search_service.dart';
import '../datasources/gallery_record_link_datasource.dart';
import '../models/catalog_object.dart';
import '../models/gallery_item.dart';
import '../models/gallery_observation_projection.dart';
import '../models/shooting_record.dart';
import 'catalog_repository.dart';
import 'gallery_repository.dart';
import 'shooting_record_repository.dart';

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
  }) => GalleryShootingRecordRepositoryAdapter._(
    galleryRepository,
    localRepository,
    catalogRepository,
    projectionMapper,
    linkDataSource,
  );

  GalleryShootingRecordRepositoryAdapter._(
    this._galleryRepository,
    this._localRepository,
    this._catalogRepository,
    this._projectionMapper,
    this._linkDataSource,
  );

  final GalleryRepository _galleryRepository;
  final ShootingRecordRepository _localRepository;
  final CatalogRepository _catalogRepository;
  final GalleryObservationProjectionMapper _projectionMapper;
  final GalleryRecordLinkDataSource _linkDataSource;
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
      final linkedLocalId = links[item.backendRecordId];
      final localRecord = linkedLocalId == null ? null : localById[linkedLocalId];
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
      final localRecord = _isRemoteOnly(id)
          ? null
          : await _localRepository.getById(id);
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
      (await getAll()).where((record) => record.celestialObjectId == id).toList();

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
  Future<void> save(ShootingRecord record) => _localRepository.save(record);

  @override
  Future<void> update(ShootingRecord record) async {
    if (_isRemoteOnly(record.id)) {
      _lastRemoteRecords = {..._lastRemoteRecords, record.id: record};
      return;
    }
    await _localRepository.update(record);
  }

  @override
  Future<void> delete(String id) async {
    if (_isRemoteOnly(id)) {
      final updated = Map<String, ShootingRecord>.from(_lastRemoteRecords)
        ..remove(id);
      _lastRemoteRecords = updated;
      return;
    }
    await _localRepository.delete(id);
  }

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) =>
      _localRepository.clearRepresentativeForObject(celestialObjectId);

  @override
  Future<void> setRepresentative(String recordId) async {
    if (_isRemoteOnly(recordId)) return;
    await _localRepository.setRepresentative(recordId);
  }
}
