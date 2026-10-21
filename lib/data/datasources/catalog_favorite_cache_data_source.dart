import 'dart:convert';

import '../models/catalog_favorite.dart';
import 'gallery_cache_local_datasource.dart';

abstract interface class CatalogFavoriteCacheDataSource {
  Future<List<CatalogFavorite>> read();
  Future<void> write(List<CatalogFavorite> favorites);
}

class CatalogFavoriteCacheLocalDataSource
    implements CatalogFavoriteCacheDataSource {
  CatalogFavoriteCacheLocalDataSource(this._cache);

  static const cacheKey = 'catalog:favorites:v1';

  final GalleryCacheDataSource _cache;

  @override
  Future<List<CatalogFavorite>> read() async {
    final entry = await _cache.read(cacheKey);
    if (entry == null) return const [];
    try {
      final decoded = jsonDecode(entry.payloadJson);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => CatalogFavorite.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> write(List<CatalogFavorite> favorites) => _cache.write(
    GalleryCacheEntry(
      key: cacheKey,
      payloadJson: jsonEncode(
        favorites.map((favorite) => favorite.toJson()).toList(growable: false),
      ),
      cachedAt: DateTime.now().toUtc(),
    ),
  );
}
