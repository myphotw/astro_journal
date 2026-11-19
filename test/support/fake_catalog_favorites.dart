import 'package:astro_journal/data/datasources/catalog_favorite_cache_data_source.dart';
import 'package:astro_journal/data/models/catalog_favorite.dart';
import 'package:astro_journal/services/tc_backend_catalog_favorite_service.dart';

CatalogFavorite favoriteForTest(String id) => CatalogFavorite(
  catalogObjectId: id,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class FakeCatalogFavoritesRemote implements CatalogFavoriteRemoteApi {
  FakeCatalogFavoritesRemote(Iterable<String> initial) : ids = {...initial};

  final Set<String> ids;

  @override
  Future<List<CatalogFavorite>> list() async =>
      ids.map(favoriteForTest).toList();

  @override
  Future<CatalogFavorite> add(String catalogObjectId) async {
    ids.add(catalogObjectId);
    return favoriteForTest(catalogObjectId);
  }

  @override
  Future<CatalogFavoriteDeleteResult> remove(String catalogObjectId) async =>
      CatalogFavoriteDeleteResult(
        catalogObjectId: catalogObjectId,
        deleted: ids.remove(catalogObjectId),
      );
}

class FakeCatalogFavoritesCache implements CatalogFavoriteCacheDataSource {
  FakeCatalogFavoritesCache([Iterable<String> initial = const []])
    : values = initial.map(favoriteForTest).toList();

  List<CatalogFavorite> values;

  @override
  Future<List<CatalogFavorite>> read() async => [...values];

  @override
  Future<void> write(List<CatalogFavorite> favorites) async {
    values = [...favorites];
  }
}
