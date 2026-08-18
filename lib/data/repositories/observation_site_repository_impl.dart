import '../datasources/observation_site_local_datasource.dart';
import '../models/blocked_azimuth_range.dart';
import '../models/horizon_point.dart';
import '../models/observation_site.dart';
import 'observation_site_repository.dart';

class ObservationSiteRepositoryImpl implements ObservationSiteRepository {
  ObservationSiteRepositoryImpl({ObservationSiteLocalDataSource? dataSource})
    : _dataSource = dataSource ?? ObservationSiteLocalDataSource();

  final ObservationSiteLocalDataSource _dataSource;

  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) =>
      _dataSource.addBlockedRange(range);

  @override
  Future<void> addHorizonPoint(HorizonPoint point) =>
      _dataSource.addHorizonPoint(point);

  @override
  Future<void> create(ObservationSite site) => _dataSource.create(site);

  @override
  Future<void> delete(String id, {bool hard = false}) =>
      _dataSource.delete(id, hard: hard);

  @override
  Future<void> deleteBlockedRange(String id) =>
      _dataSource.deleteBlockedRange(id);

  @override
  Future<void> deleteHorizonPoint(String id) =>
      _dataSource.deleteHorizonPoint(id);

  @override
  Future<ObservationSite?> get(String id, {bool includeDeleted = false}) =>
      _dataSource.get(id, includeDeleted: includeDeleted);

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) =>
      _dataSource.list(includeDeleted: includeDeleted);

  @override
  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) =>
      _dataSource.listBlockedRanges(siteId);

  @override
  Future<List<HorizonPoint>> listHorizonPoints(String siteId) =>
      _dataSource.listHorizonPoints(siteId);

  @override
  Future<void> markLastUsed(String id, DateTime usedAt) =>
      _dataSource.markLastUsed(id, usedAt);

  @override
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) => _dataSource.replaceBlockedRanges(siteId, ranges);

  @override
  Future<void> replaceHorizonPoints(String siteId, List<HorizonPoint> points) =>
      _dataSource.replaceHorizonPoints(siteId, points);

  @override
  Future<void> setFavorite(String id, bool favorite) =>
      _dataSource.setFavorite(id, favorite);

  @override
  Future<void> update(ObservationSite site) => _dataSource.update(site);

  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) =>
      _dataSource.updateBlockedRange(range);

  @override
  Future<void> updateHorizonPoint(HorizonPoint point) =>
      _dataSource.updateHorizonPoint(point);
}
