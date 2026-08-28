import 'dart:convert';

import '../../services/tc_backend_settings_service.dart';
import '../datasources/gallery_cache_local_datasource.dart';
import '../datasources/remote_gallery_datasource.dart';
import '../models/gallery_item.dart';
import '../models/plate_solve_queue.dart';
import 'gallery_repository.dart';
import '../../services/tc_backend_auth_service.dart';

typedef GalleryRemoteFactory = GalleryRemoteDataSource Function(String baseUrl);

class HybridGalleryRepository implements GalleryRepository {
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

  @override
  Future<List<GalleryItem>> getAll({bool forceRefresh = false}) async =>
      (await getSnapshot(forceRefresh: forceRefresh)).items;

  @override
  Future<GallerySnapshot> getSnapshot({bool forceRefresh = false}) async {
    const key = 'astro:gallery:list';
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(key);
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
    if (!forceRefresh && _isFresh(cached, listTtl)) {
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
      await _write(key, synced.map((item) => item.toJson()).toList());
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
  }) async {
    const listKey = 'astro:gallery:list';
    final listEntry = await _cache.read(listKey);
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
      await _write(listKey, rewritten.map((item) => item.toJson()).toList());
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
  Future<void> applyLocalDelete(String backendRecordId) async {
    const listKey = 'astro:gallery:list';
    final entry = await _cache.read(listKey);
    if (entry != null) {
      final remaining = _cachedItems(entry)
          .where((item) => item.backendRecordId != backendRecordId)
          .map((item) => item.toJson())
          .toList(growable: false);
      await _write(listKey, remaining);
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
    for (final item in _cachedItems(await _cache.read('astro:gallery:list'))) {
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
  Future<bool> upsertPulledItem(GalleryItem item) async {
    final currentRevision = await getCachedRevision(item.backendRecordId);
    if (currentRevision != null && currentRevision >= item.revision) {
      return false;
    }
    const listKey = 'astro:gallery:list';
    final current = _cachedItems(await _cache.read(listKey));
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
    await _write(listKey, updated.map((entry) => entry.toJson()).toList());
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
  }) async {
    final tombstoneKey = 'astro:gallery:tombstone:$backendRecordId';
    final existingTombstone = _tombstone(await _cache.read(tombstoneKey));
    if (existingTombstone != null && existingTombstone.revision >= revision) {
      return false;
    }
    final currentRevision = await getCachedRevision(backendRecordId);
    if (currentRevision != null && currentRevision > revision) return false;
    await applyLocalDelete(backendRecordId);
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
    return status != PlateSolveQueueStatus.completed || item.plateSolve != null;
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

  Future<void> _write(String key, Object payload) => _cache.write(
    GalleryCacheEntry(
      key: key,
      payloadJson: jsonEncode(payload),
      cachedAt: _now().toUtc(),
    ),
  );
}
