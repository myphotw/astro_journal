import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/datasources/catalog_favorite_cache_data_source.dart';
import '../data/models/catalog_favorite.dart';
import '../data/models/catalog_object.dart';
import '../data/repositories/catalog_repository.dart';
import 'tc_backend_catalog_favorite_service.dart';

class CatalogFavoriteActionException implements Exception {
  const CatalogFavoriteActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CatalogFavoriteController extends ChangeNotifier {
  CatalogFavoriteController({
    required CatalogFavoriteRemoteApi remoteApi,
    required CatalogFavoriteCacheDataSource cache,
    required CatalogRepository catalogRepository,
  }) : this._internal(remoteApi, cache, catalogRepository);

  CatalogFavoriteController._internal(
    this._remoteApi,
    this._cache,
    this._catalogRepository,
  );

  final CatalogFavoriteRemoteApi _remoteApi;
  final CatalogFavoriteCacheDataSource _cache;
  final CatalogRepository _catalogRepository;

  final Map<String, CatalogFavorite> _favorites = {};
  final Map<String, CatalogObject> _objects = {};
  final Set<String> _pendingIds = {};
  Future<void>? _refreshFuture;
  bool _initialized = false;
  bool _refreshing = false;
  String? _lastSyncError;

  bool get initialized => _initialized;
  bool get refreshing => _refreshing;
  String? get lastSyncError => _lastSyncError;
  Set<String> get favoriteIds => Set.unmodifiable(_favorites.keys.toSet());
  List<CatalogObject> get favoriteObjects => List.unmodifiable(_objects.values);

  bool isFavorite(String catalogObjectId) =>
      _favorites.containsKey(catalogObjectId);

  bool isPending(String catalogObjectId) =>
      _pendingIds.contains(catalogObjectId);

  Future<void> initialize() async {
    if (_initialized) return refreshFromServer();
    final cached = await _cache.read();
    await _replace(cached, persist: false);
    _initialized = true;
    notifyListeners();
    try {
      await refreshFromServer();
    } catch (_) {
      // 캐시는 계속 표시하고 서버 오류는 lastSyncError로 노출한다.
    }
  }

  Future<void> refreshFromServer() {
    final active = _refreshFuture;
    if (active != null) return active;
    final future = _refreshFromServer();
    _refreshFuture = future;
    return future.whenComplete(() => _refreshFuture = null);
  }

  Future<void> _refreshFromServer() async {
    _refreshing = true;
    notifyListeners();
    try {
      final remote = await _remoteApi.list();
      await _replace(remote, persist: true);
      _lastSyncError = null;
    } catch (error) {
      _lastSyncError = _messageFor(error);
      rethrow;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> toggle(String catalogObjectId) async {
    if (_pendingIds.contains(catalogObjectId)) return;
    final object = await _catalogRepository.getById(catalogObjectId);
    if (object == null || object.isDeleted) {
      throw const CatalogFavoriteActionException('카탈로그에서 해당 천체를 찾을 수 없습니다.');
    }

    _pendingIds.add(catalogObjectId);
    notifyListeners();
    try {
      if (isFavorite(catalogObjectId)) {
        await _remoteApi.remove(catalogObjectId);
        _favorites.remove(catalogObjectId);
        _objects.remove(catalogObjectId);
      } else {
        final favorite = await _remoteApi.add(catalogObjectId);
        _favorites[catalogObjectId] = favorite;
        _objects[catalogObjectId] = object;
      }
      await _cache.write(_orderedFavorites());
      _lastSyncError = null;
    } catch (error) {
      _lastSyncError = _messageFor(error);
      throw CatalogFavoriteActionException(_lastSyncError!);
    } finally {
      _pendingIds.remove(catalogObjectId);
      notifyListeners();
    }
  }

  Future<void> _replace(
    List<CatalogFavorite> values, {
    required bool persist,
  }) async {
    final nextFavorites = {
      for (final favorite in values) favorite.catalogObjectId: favorite,
    };
    final nextObjects = <String, CatalogObject>{};
    for (final id in nextFavorites.keys) {
      final object = await _catalogRepository.getById(id);
      if (object != null && !object.isDeleted) nextObjects[id] = object;
    }
    _favorites
      ..clear()
      ..addAll(nextFavorites);
    _objects
      ..clear()
      ..addAll(nextObjects);
    if (persist) await _cache.write(_orderedFavorites());
  }

  List<CatalogFavorite> _orderedFavorites() {
    final values = _favorites.values.toList(growable: false);
    values.sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0
          ? byCreated
          : a.catalogObjectId.compareTo(b.catalogObjectId);
    });
    return values;
  }

  static String _messageFor(Object error) {
    if (error is CatalogFavoriteRemoteException) return error.message;
    if (error is CatalogFavoriteActionException) return error.message;
    return '즐겨찾기를 동기화하지 못했습니다.';
  }
}
