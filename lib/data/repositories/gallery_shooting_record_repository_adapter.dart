import '../../services/catalog_search_service.dart';
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
    required DateTime fallbackTime,
  }) => GalleryObservationProjection.fromGalleryItem(
    item,
    fallbackTime: fallbackTime,
  );

  String? resolveCatalogObjectId(
    GalleryObservationProjection projection,
    List<CatalogObject> catalog,
  ) {
    final directId = projection.catalogObjectId?.trim();
    if (directId != null && directId.isNotEmpty) {
      for (final object in catalog) {
        if (object.id.toLowerCase() == directId.toLowerCase()) {
          return object.id;
        }
      }
    }
    return _catalogSearchService
        .resolveTarget(projection.targetName ?? directId, catalog)
        ?.id;
  }
}

/// Read adapter for the existing GalleryViewModel contract.
///
/// Mutations remain local-only until Astro ObservationRecord mutation APIs are
/// available. Remote-only rows are therefore safe no-ops for repository writes;
/// GalleryViewModel still reflects the change for the current UI session.
class GalleryShootingRecordRepositoryAdapter
    implements ShootingRecordRepository {
  factory GalleryShootingRecordRepositoryAdapter({
    required GalleryRepository galleryRepository,
    required ShootingRecordRepository localRepository,
    required CatalogRepository catalogRepository,
    required GalleryObservationProjectionMapper projectionMapper,
    DateTime Function()? now,
  }) => GalleryShootingRecordRepositoryAdapter._(
    galleryRepository,
    localRepository,
    catalogRepository,
    projectionMapper,
    now ?? DateTime.now,
  );

  GalleryShootingRecordRepositoryAdapter._(
    this._galleryRepository,
    this._localRepository,
    this._catalogRepository,
    this._projectionMapper,
    this._now,
  );

  final GalleryRepository _galleryRepository;
  final ShootingRecordRepository _localRepository;
  final CatalogRepository _catalogRepository;
  final GalleryObservationProjectionMapper _projectionMapper;
  final DateTime Function() _now;
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
    final localById = {for (final record in local) record.id: record};
    final localByFilename = {
      for (final record in local)
        if (record.originalFilename?.isNotEmpty == true)
          record.originalFilename!: record,
    };
    final projected = <ShootingRecord>[];
    for (final item in snapshot.items) {
      final projection = _projectionMapper.toProjection(
        item,
        fallbackTime: _now(),
      );
      final localRecord = localById[projection.localRecordId] ??
          localByFilename[projection.originalFilename];
      projected.add(
        projection.toShootingRecord(
          localRecord: localRecord,
          resolvedCatalogObjectId: _projectionMapper.resolveCatalogObjectId(
            projection,
            catalog,
          ),
        ),
      );
    }
    _lastRemoteRecords = {for (final record in projected) record.id: record};
    return projected;
  }

  bool _isRemoteOnly(String id) =>
      id.startsWith('remote:') && _lastRemoteRecords.containsKey(id);

  @override
  Future<ShootingRecord?> getById(String id) async =>
      _lastRemoteRecords[id] ?? _localRepository.getById(id);

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
