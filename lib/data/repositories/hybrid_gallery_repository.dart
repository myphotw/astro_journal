import 'dart:convert';

import '../../services/tc_backend_settings_service.dart';
import '../datasources/gallery_cache_local_datasource.dart';
import '../datasources/remote_gallery_datasource.dart';
import '../models/gallery_item.dart';
import 'gallery_repository.dart';

typedef GalleryRemoteFactory = GalleryRemoteDataSource Function(String baseUrl);

class HybridGalleryRepository implements GalleryRepository {
  factory HybridGalleryRepository({
    required TcBackendSettingsService settingsService,
    required GalleryCacheDataSource cache,
    GalleryRemoteFactory? remoteFactory,
    DateTime Function()? now,
    Duration listTtl = const Duration(minutes: 30),
    Duration detailTtl = const Duration(hours: 24),
  }) => HybridGalleryRepository._(
    settingsService,
    cache,
    remoteFactory ??
        ((baseUrl) => RemoteGalleryDataSource(baseUrl: baseUrl)),
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
    const key = 'gallery:list';
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
      final synced = fetched
          .map((item) => item.copyWith(syncedAt: syncedAt))
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
    String backendFileId, {
    bool forceRefresh = false,
  }) async {
    final key = 'gallery:detail:$backendFileId';
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(key);
    if (!settings.enabled || baseUrl == null) return _cachedItem(cached);
    if (!forceRefresh && _isFresh(cached, detailTtl)) {
      return _cachedItem(cached);
    }
    try {
      final fetched = await _remoteFactory(baseUrl).getDetail(backendFileId);
      final synced = fetched.copyWith(syncedAt: _now());
      await _write(key, synced.toJson());
      return synced;
    } on RemoteGalleryException {
      return _cachedItem(cached);
    }
  }

  @override
  Future<List<GalleryItem>> search(
    String query, {
    bool forceRefresh = false,
  }) => _items(
    key: 'gallery:search:${Uri.encodeQueryComponent(query.trim())}',
    ttl: listTtl,
    forceRefresh: forceRefresh,
    remote: (source) => source.search(query),
  );

  @override
  Future<Map<String, dynamic>> getTimeline({bool forceRefresh = false}) =>
      _map(
        key: 'gallery:timeline',
        forceRefresh: forceRefresh,
        remote: (source) => source.getTimeline(),
      );

  @override
  Future<Map<String, dynamic>> getStatistics({bool forceRefresh = false}) =>
      _map(
        key: 'gallery:statistics',
        forceRefresh: forceRefresh,
        remote: (source) => source.getStatistics(),
      );

  Future<List<GalleryItem>> _items({
    required String key,
    required Duration ttl,
    required bool forceRefresh,
    required Future<List<GalleryItem>> Function(GalleryRemoteDataSource) remote,
  }) async {
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(key);
    if (!settings.enabled || baseUrl == null) return _cachedItems(cached);
    if (!forceRefresh && _isFresh(cached, ttl)) return _cachedItems(cached);
    try {
      final syncedAt = _now();
      final fetched = await remote(_remoteFactory(baseUrl));
      final synced = fetched
          .map((item) => item.copyWith(syncedAt: syncedAt))
          .toList(growable: false);
      await _write(key, synced.map((item) => item.toJson()).toList());
      return synced;
    } on RemoteGalleryException {
      return _cachedItems(cached);
    }
  }

  Future<Map<String, dynamic>> _map({
    required String key,
    required bool forceRefresh,
    required Future<Map<String, dynamic>> Function(GalleryRemoteDataSource)
    remote,
  }) async {
    final settings = await _settingsService.load();
    final baseUrl = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    final cached = await _cache.read(key);
    if (!settings.enabled || baseUrl == null) return _cachedMap(cached);
    if (!forceRefresh && _isFresh(cached, listTtl)) return _cachedMap(cached);
    try {
      final fetched = await remote(_remoteFactory(baseUrl));
      await _write(key, fetched);
      return fetched;
    } on RemoteGalleryException {
      return _cachedMap(cached);
    }
  }

  bool _isFresh(GalleryCacheEntry? entry, Duration ttl) =>
      entry != null && _now().difference(entry.cachedAt) <= ttl;

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

  Map<String, dynamic> _cachedMap(GalleryCacheEntry? entry) {
    if (entry == null) return const {};
    try {
      return Map<String, dynamic>.from(jsonDecode(entry.payloadJson) as Map);
    } on Object {
      return const {};
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
