import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/datasources/catalog_favorite_cache_data_source.dart';
import '../data/models/catalog_favorite.dart';
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
  final Set<String> _pendingIds = {};
  Set<String> _favoriteIds = const {};
  Future<void> _queue = Future.value();
  Future<void>? _cacheFuture;
  Future<void>? _refreshFuture;
  bool _initialized = false;
  bool _refreshing = false;
  bool _disposed = false;
  String? _lastSyncError;

  bool get initialized => _initialized;
  bool get refreshing => _refreshing;
  String? get lastSyncError => _lastSyncError;
  Set<String> get favoriteIds => _favoriteIds;

  bool isFavorite(String catalogObjectId) =>
      _favorites.containsKey(catalogObjectId);

  bool isPending(String catalogObjectId) =>
      _pendingIds.contains(catalogObjectId);

  Future<void> initialize() async {
    try {
      await refreshFromServer();
    } catch (_) {
      // 캐시는 계속 표시하고 서버 오류는 lastSyncError로 노출한다.
    }
  }

  Future<void> restoreCache() => _cacheFuture ??= _restoreCache();

  Future<void> _restoreCache() async {
    try {
      _replace(await _cache.read());
    } catch (_) {
      _lastSyncError = '저장된 유명천체 목록을 불러오지 못했습니다.';
    } finally {
      _initialized = true;
      _notify();
    }
  }

  Future<void> refreshFromServer() {
    final active = _refreshFuture;
    if (active != null) return active;
    return _refreshFuture = _serialize(_refreshFromServer).whenComplete(
      () => _refreshFuture = null,
    );
  }

  Future<void> _refreshFromServer() async {
    await restoreCache();
    _refreshing = true;
    _notify();
    try {
      final remote = await _remoteApi.list();
      _lastSyncError = null;
      _replace(remote);
      _notify();
      await _saveCache();
    } catch (error) {
      _lastSyncError = _messageFor(error);
      rethrow;
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> toggle(String catalogObjectId) async {
    if (_pendingIds.contains(catalogObjectId)) return;
    _pendingIds.add(catalogObjectId);
    // Keep the action the user clicked even if a pending refresh changes
    // the server snapshot before this mutation reaches the front of the queue.
    final remove = isFavorite(catalogObjectId);
    _notify();
    try {
      await _serialize(() async {
        await restoreCache();
        final object = await _catalogRepository.getById(catalogObjectId);
        if (object == null || object.isDeleted || object.id != catalogObjectId) {
          throw const CatalogFavoriteActionException('카탈로그에서 해당 천체를 찾을 수 없습니다.');
        }
        if (remove) {
          final result = await _remoteApi.remove(catalogObjectId);
          if (result.catalogObjectId != catalogObjectId) {
            throw const FormatException('Mismatched favorite ID.');
          }
          _favorites.remove(catalogObjectId);
        } else {
          final favorite = await _remoteApi.add(catalogObjectId);
          if (favorite.catalogObjectId != catalogObjectId) {
            throw const FormatException('Mismatched favorite ID.');
          }
          _favorites[catalogObjectId] = favorite;
        }
        _lastSyncError = null;
        _updateIds();
        _notify();
        await _saveCache();
      });
    } catch (error) {
      _lastSyncError = _messageFor(error);
      throw CatalogFavoriteActionException(_lastSyncError!);
    } finally {
      _pendingIds.remove(catalogObjectId);
      _notify();
    }
  }

  void _replace(List<CatalogFavorite> values) {
    _favorites
      ..clear()
      ..addEntries(values.map((value) => MapEntry(value.catalogObjectId, value)));
    _updateIds();
  }

  void _updateIds() {
    if (_favoriteIds.length != _favorites.length ||
        !_favoriteIds.every(_favorites.containsKey)) {
      _favoriteIds = Set.unmodifiable(_favorites.keys);
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    final run = _queue.then((_) async {
      if (!_disposed) await action();
    });
    _queue = run.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  Future<void> _saveCache() async {
    try {
      await _cache.write(_orderedFavorites());
    } catch (_) {
      // The server already accepted the change. Do not roll back its UI state.
      _lastSyncError = '유명천체 목록을 기기에 저장하지 못했습니다.';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
    return '유명천체를 동기화하지 못했습니다.';
  }
}
