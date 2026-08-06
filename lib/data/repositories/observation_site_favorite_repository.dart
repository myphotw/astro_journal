import '../models/observation_site_favorite.dart';

abstract class ObservationSiteFavoriteRepository {
  Future<List<ObservationSiteFavorite>> getAll();
  Future<ObservationSiteFavorite?> getById(String id);
  Future<void> save(ObservationSiteFavorite favorite);
  Future<void> delete(String id);
}
