import '../datasources/observation_site_favorite_local_datasource.dart';
import '../models/observation_site_favorite.dart';
import 'observation_site_favorite_repository.dart';

class ObservationSiteFavoriteRepositoryImpl
    implements ObservationSiteFavoriteRepository {
  ObservationSiteFavoriteRepositoryImpl({ObservationSiteFavoriteLocalDataSource? dataSource})
      : _dataSource = dataSource ?? ObservationSiteFavoriteLocalDataSource();

  final ObservationSiteFavoriteLocalDataSource _dataSource;

  @override
  Future<List<ObservationSiteFavorite>> getAll() => _dataSource.getAll();

  @override
  Future<ObservationSiteFavorite?> getById(String id) => _dataSource.getById(id);

  @override
  Future<void> save(ObservationSiteFavorite favorite) =>
      _dataSource.insert(favorite);

  @override
  Future<void> delete(String id) => _dataSource.delete(id);
}
