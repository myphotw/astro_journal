import 'dart:async';
import 'dart:convert';

import '../../services/app_logger.dart';
import '../../services/tc_backend_settings_service.dart';
import '../datasources/gallery_cache_local_datasource.dart';
import '../datasources/remote_gallery_datasource.dart';
import '../models/gallery_item.dart';
import '../models/plate_solve_queue.dart';
import 'gallery_repository.dart';
import '../../services/tc_backend_auth_service.dart';

typedef GalleryRemoteFactory = GalleryRemoteDataSource Function(String baseUrl);

class HybridGalleryRepository implements GalleryRepository {
  static const _listCacheKey = 'astro:gallery:list';
  static const _fullSnapshotCacheKey = 'astro:gallery:full_snapshot';

  factory HybridGalleryRepository({
    required TcBackendSettingsService settingsService,
    required GalleryCacheDataSource cache,
    GalleryRemoteFactory? remoteFactory,
    DateTime Function()? now,
    Duration listTtl = const Duration(minutes: 30),
    Duration detailTtl = const Duration(hours: 24),
    TcBackendAuthHeaders? authHeaders,
  }) => HybridGalleryRepository._(
    settingsService,
    cache,
    remoteFactory ??
        ((baseUrl) => RemoteGalleryDataSource(
          baseUrl: baseUrl,
          authHeaders: authHeaders,
        )),
    now ?? DateTime.now,
    listTtl,
    detailTtl,
  );

  HybridGalleryRepository._(
    this._settingsService,
    this._cache,
    this._remoteFactory,
    this._now,
    this.listTtl,
    this.detailTtl,
  );

  final TcBackendSettingsService _settingsService;
  final GalleryCacheDataSource _cache;
  final GalleryRemoteFactory _remoteFactory;
  final DateTime Function() _now;
  final Duration listTtl;
  final Duration detailTtl;
  Future<void> _listMutationTail = Future<void>.value();

  @override
  Future<List<GalleryItem>> getAll({bool forceRefresh = false}) async =>
      (await getSnapshot(forceRefresh: forceRefresh)).items;

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) =>
      _serializeListMutation(
        () => _getSnapshotLocked(forceRefresh: forceRefresh),
      );

  Future<GallerySnapshot> _getSnapshotLocked({
    required bool forceRefresh,
  }) async {
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(_listCacheKey);
    final fullSnapshot = await _cache.read(_fullSnapshotCacheKey);
    final cachedItems = _cachedItems(cached);
    if (!settings.enabled || baseUrl == null) {
      return GallerySnapshot(
        items: cachedItems,
        source: cached == null
            ? GallerySnapshotSource.none
            : GallerySnapshotSource.cache,
        backendEnabled: false,
      );
    }
    if (!forceRefresh &&
        cached != null &&
        _isFresh(fullSnapshot, listTtl)) {
      return GallerySnapshot(
        items: cachedItems,
        source: GallerySnapshotSource.cache,
        backendEnabled: true,
      );
    }
    try {
      final syncedAt = _now();
      final fetched = await _remoteFactory(baseUrl).getGallery();
      final cachedByRecordId = {
        for (final item in cachedItems) item.backendRecordId: item,
      };
      final synced = fetched
          .map(
            (item) => item.copyWith(
              syncedAt: syncedAt,
              plateSolveStatus:
                  item.plateSolveStatus ??
                  cachedByRecordId[item.backendRecordId]?.plateSolveStatus,
              plateSolveJobId:
                  item.plateSolveJobId ??
                  cachedByRecordId[item.backendRecordId]?.plateSolveJobId,
              plateSolve:
                  item.plateSolve ??
                  cachedByRecordId[item.backendRecordId]?.plateSolve,
            ),
          )
          .toList(growable: false);
      await _write(
        _listCacheKey,
        synced.map((item) => item.toJson()).toList(),
      );
      await _write(_fullSnapshotCacheKey, const {'completed': true});
      return GallerySnapshot(
        items: synced,
        source: GallerySnapshotSource.remote,
        backendEnabled: true,
      );
    } on RemoteGalleryException {
      return GallerySnapshot(
        items: cachedItems,
        source: cached == null
            ? GallerySnapshotSource.none
            : GallerySnapshotSource.cache,
        backendEnabled: true,
        remoteFailed: true,
      );
    }
  }

  @override
  Future<GalleryItem?> getById(
    String backendRecordId, {
    bool forceRefresh = false,
  }) async {
    final key = 'astro:gallery:detail:$backendRecordId';
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(key);
    final cachedItem = _cachedItem(cached);
    if (cachedItem?.plateSolve != null) {
      AppLogger.info(
        'HybridGalleryRepository',
        '[WCS_DEBUG] gallery_cache_read '
            'backend_record_id=$backendRecordId '
            'wcs=${cachedItem?.plateSolve?.wcs != null}',
      );
    }
    if (!settings.enabled || baseUrl == null) return cachedItem;
    // Older/current Gallery detail cache entries can legitimately lack the
    // numeric CommonFile identity because Astro Gallery exposes only its
    // SHA-256 `file_id`. Do not let a fresh but incomplete cache prevent the
    // remote detail datasource from recovering the canonical record `file_id`.
    if (!forceRefresh &&
        _isDetailHydrated(cachedItem) &&
        _isFresh(cached, detailTtl)) {
      return cachedItem;
    }
    try {
      final fetched = await _remoteFactory(baseUrl).getDetail(backendRecordId);
      final synced = fetched.copyWith(
        syncedAt: _now(),
        plateSolveStatus:
            fetched.plateSolveStatus ?? cachedItem?.plateSolveStatus,
        plateSolveJobId: fetched.plateSolveJobId ?? cachedItem?.plateSolveJobId,
        plateSolve: fetched.plateSolve ?? cachedItem?.plateSolve,
      );
      if (synced.plateSolve != null) {
        AppLogger.info(
          'HybridGalleryRepository',
          '[WCS_DEBUG] gallery_cache_write '
              'backend_record_id=$backendRecordId '
              'wcs=${synced.plateSolve?.wcs != null}',
        );
      }
      await _write(key, synced.toJson());
      return synced;
    } on RemoteGalleryException {
      return cachedItem;
    }
  }

  @override
  Future<List<GalleryItem>> search(
    String query, {
    bool forceRefresh = false,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return getAll(forceRefresh: forceRefresh);
    return (await getAll(forceRefresh: forceRefresh))
        .where((item) {
          return item.catalogObjectId.toLowerCase().contains(normalized) ||
              (item.originalFilename?.toLowerCase().contains(normalized) ??
                  false) ||
              (item.location?.toLowerCase().contains(normalized) ?? false) ||
              item.memo.toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> getTimeline({bool forceRefresh = false}) async {
    final buckets = <String, int>{};
    for (final item in await getAll(forceRefresh: forceRefresh)) {
      final date = item.capturedAt;
      final key =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}';
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    return {'buckets': buckets};
  }

  @override
  Future<Map<String, dynamic>> getStatistics({
    bool forceRefresh = false,
  }) async {
    final items = await getAll(forceRefresh: forceRefresh);
    return {
      'total': items.length,
      'favorites': items.where((item) => item.favorite).length,
    };
  }

  @override
  Future<void> applyLocalPatch(
    String backendRecordId,
    Map<String, Object?> fields, {
    int? revision,
  }) => _serializeListMutation(
    () => _applyLocalPatchLocked(
      backendRecordId,
      fields,
      revision: revision,
    ),
  );

  Future<void> _applyLocalPatchLocked(
    String backendRecordId,
    Map<String, Object?> fields, {
    int? revision,
  }) async {
    final listEntry = await _cache.read(_listCacheKey);
    final items = _cachedItems(listEntry);
    GalleryItem? target;
    for (final item in items) {
      if (item.backendRecordId == backendRecordId) {
        target = item;
        break;
      }
    }
    if (target != null) {
      final updated = _applyFields(target, fields, revision: revision);
      final representative = fields['representative'] == true;
      final rewritten = items
          .map((item) {
            if (item.backendRecordId == backendRecordId) return updated;
            if (representative &&
                item.catalogObjectId == target!.catalogObjectId) {
              return item.copyWith(representative: false);
            }
            return item;
          })
          .toList(growable: false);
      await _write(
        _listCacheKey,
        rewritten.map((item) => item.toJson()).toList(),
      );
    }

    final detailKey = 'astro:gallery:detail:$backendRecordId';
    final detail = _cachedItem(await _cache.read(detailKey));
    if (detail != null) {
      await _write(
        detailKey,
        _applyFields(detail, fields, revision: revision).toJson(),
      );
    }
  }

  @override
  Future<void> applyLocalDelete(String backendRecordId) =>
      _serializeListMutation(() => _applyLocalDeleteLocked(backendRecordId));

  Future<void> _applyLocalDeleteLocked(String backendRecordId) async {
    final entry = await _cache.read(_listCacheKey);
    if (entry != null) {
      final before = _cachedItems(entry);
      final remaining = before
          .where((item) => item.backendRecordId != backendRecordId)
          .toList(growable: false);
      await _write(
        _listCacheKey,
        remaining.map((item) => item.toJson()).toList(growable: false),
      );
    }
    // An invalidated detail entry parses as null and cannot resurrect a
    // locally deleted record while the durable DELETE is pending.
    await _write('astro:gallery:detail:$backendRecordId', const {});
  }

  @override
  Future<int?> getCachedRevision(String backendRecordId) async {
    final revisions = <int>[];
    final detail = _cachedItem(
      await _cache.read('astro:gallery:detail:$backendRecordId'),
    );
    if (detail != null) revisions.add(detail.revision);
    for (final item in _cachedItems(await _cache.read(_listCacheKey))) {
      if (item.backendRecordId == backendRecordId) {
        revisions.add(item.revision);
        break;
      }
    }
    final tombstone = _tombstone(
      await _cache.read('astro:gallery:tombstone:$backendRecordId'),
    );
    if (tombstone != null) revisions.add(tombstone.revision);
    if (revisions.isEmpty) return null;
    return revisions.reduce((left, right) => left > right ? left : right);
  }

  @override
  Future<bool> upsertPulledItem(GalleryItem item) =>
      _serializeListMutation(() => _upsertPulledItemLocked(item));

  Future<bool> _upsertPulledItemLocked(GalleryItem item) async {
    final currentRevision = await getCachedRevision(item.backendRecordId);
    if (currentRevision != null && currentRevision >= item.revision) {
      return false;
    }
    final current = _cachedItems(await _cache.read(_listCacheKey));
    final synced = item.copyWith(syncedAt: _now(), syncState: 'SYNCED');
    var replaced = false;
    final updated = current.map((existing) {
      if (existing.backendRecordId != item.backendRecordId) return existing;
      replaced = true;
      return synced.copyWith(
        plateSolveJobId: synced.plateSolveJobId ?? existing.plateSolveJobId,
        plateSolve: synced.plateSolve ?? existing.plateSolve,
      );
    }).toList();
    if (!replaced) updated.add(synced);
    await _write(
      _listCacheKey,
      updated.map((entry) => entry.toJson()).toList(),
    );
    final detailKey = 'astro:gallery:detail:${item.backendRecordId}';
    final existingDetail = _cachedItem(await _cache.read(detailKey));
    final mergedDetail = synced.copyWith(
      plateSolveJobId:
          synced.plateSolveJobId ?? existingDetail?.plateSolveJobId,
      plateSolve: synced.plateSolve ?? existingDetail?.plateSolve,
    );
    await _write(detailKey, mergedDetail.toJson());
    return true;
  }

  @override
  Future<bool> applyPulledDelete(
    String backendRecordId, {
    required int revision,
    DateTime? deletedAt,
  }) => _serializeListMutation(
    () => _applyPulledDeleteLocked(
      backendRecordId,
      revision: revision,
      deletedAt: deletedAt,
    ),
  );

  Future<bool> _applyPulledDeleteLocked(
    String backendRecordId, {
    required int revision,
    DateTime? deletedAt,
  }) async {
    final tombstoneKey = 'astro:gallery:tombstone:$backendRecordId';
    final existingTombstone = _tombstone(await _cache.read(tombstoneKey));
    if (existingTombstone != null && existingTombstone.revision >= revision) {
      return false;
    }
    final currentRevision = await getCachedRevision(backendRecordId);
    if (currentRevision != null && currentRevision > revision) return false;
    await _applyLocalDeleteLocked(backendRecordId);
    await _write(tombstoneKey, {
      'record_id': backendRecordId,
      'revision': revision,
      'deleted_at': (deletedAt ?? _now()).toUtc().toIso8601String(),
    });
    return true;
  }

  GalleryItem _applyFields(
    GalleryItem item,
    Map<String, Object?> fields, {
    int? revision,
  }) => item.copyWith(
    revision: revision,
    favorite: fields.containsKey('favorite')
        ? fields['favorite'] as bool?
        : null,
    representative: fields.containsKey('representative')
        ? fields['representative'] as bool?
        : null,
    memo: fields.containsKey('memo') ? fields['memo'] as String? : null,
    location: fields['location_name'] as String?,
    updateLocation: fields.containsKey('location_name'),
    latitude: (fields['latitude'] as num?)?.toDouble(),
    updateLatitude: fields.containsKey('latitude'),
    longitude: (fields['longitude'] as num?)?.toDouble(),
    updateLongitude: fields.containsKey('longitude'),
    syncState: revision == null ? 'QUEUED' : 'SYNCED',
  );

  bool _isFresh(GalleryCacheEntry? entry, Duration ttl) =>
      entry != null && _now().difference(entry.cachedAt) <= ttl;

  bool _isDetailHydrated(GalleryItem? item) {
    if (item?.commonFileId == null) return false;
    final status = item!.plateSolveStatus;
    if (status == null) return true;
    if (item.plateSolveJobId == null) return false;
    if (status != PlateSolveQueueStatus.completed) return true;
    final result = item.plateSolve;
    if (result == null) return false;
    // A legacy detail cache can contain scalar solve data without proving that
    // the current Gallery detail `wcs` contract was checked. Rehydrate it once;
    // the current mapper preserves the backend payload in rawWcsJson even when
    // an older backend record legitimately has wcs=null.
    return result.hasFullWcs || (result.rawWcsJson?.isNotEmpty ?? false);
  }

  List<GalleryItem> _cachedItems(GalleryCacheEntry? entry) {
    if (entry == null) return const [];
    try {
      final decoded = jsonDecode(entry.payloadJson);
      if (decoded is! List) return const [];
      return decoded
          .map(
            (item) => GalleryItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ).copyWith(syncedAt: entry.cachedAt),
          )
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  GalleryItem? _cachedItem(GalleryCacheEntry? entry) {
    if (entry == null) return null;
    try {
      return GalleryItem.fromJson(
        Map<String, dynamic>.from(jsonDecode(entry.payloadJson) as Map),
      ).copyWith(syncedAt: entry.cachedAt);
    } on Object {
      return null;
    }
  }

  ({int revision, DateTime? deletedAt})? _tombstone(GalleryCacheEntry? entry) {
    if (entry == null) return null;
    try {
      final decoded = jsonDecode(entry.payloadJson);
      if (decoded is! Map || decoded['revision'] is! num) return null;
      return (
        revision: (decoded['revision'] as num).toInt(),
        deletedAt: DateTime.tryParse(decoded['deleted_at']?.toString() ?? ''),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, Object payload) async {
    await _cache.write(
      GalleryCacheEntry(
        key: key,
        payloadJson: jsonEncode(payload),
        cachedAt: _now().toUtc(),
      ),
    );
  }

  Future<T> _serializeListMutation<T>(
    Future<T> Function() operation,
  ) async {
    final previous = _listMutationTail;
    final completed = Completer<void>();
    _listMutationTail = completed.future;
    try {
      await previous;
    } on Object {
      // A failed operation must not permanently block later cache work.
    }
    try {
      return await operation();
    } finally {
      completed.complete();
    }
  }
}
