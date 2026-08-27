import '../../core/services/observation_context_invalidator.dart';
import '../../core/services/performance_probe.dart';
import '../datasources/observation_site_local_datasource.dart';
import '../models/blocked_azimuth_range.dart';
import '../models/horizon_point.dart';
import '../models/observation_site.dart';
import 'observation_site_repository.dart';

class ObservationSiteRepositoryImpl implements ObservationSiteRepository {
  ObservationSiteRepositoryImpl({
    ObservationSiteLocalDataSource? dataSource,
    this.contextInvalidator,
    this.onCollectionChanged,
  }) : _dataSource = dataSource ?? ObservationSiteLocalDataSource();

  final ObservationSiteLocalDataSource _dataSource;
  final ObservationContextInvalidator? contextInvalidator;
  final Future<void> Function()? onCollectionChanged;

  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) async {
    await _dataSource.addBlockedRange(range);
    await _invalidateHorizon();
  }

  @override
  Future<void> addHorizonPoint(HorizonPoint point) async {
    await _dataSource.addHorizonPoint(point);
    await _invalidateHorizon();
  }

  @override
  Future<void> create(ObservationSite site) async {
    await _dataSource.create(site);
    await _invalidateSite();
  }

  @override
  Future<void> createFavorite(ObservationSite site) async {
    await _dataSource.create(site);
    await onCollectionChanged?.call();
  }

  @override
  Future<void> delete(String id, {bool hard = false}) async {
    await _dataSource.delete(id, hard: hard);
    await _invalidateSite();
  }

  @override
  Future<void> deleteBlockedRange(String id) async {
    await _dataSource.deleteBlockedRange(id);
    await _invalidateHorizon();
  }

  @override
  Future<void> deleteHorizonPoint(String id) async {
    await _dataSource.deleteHorizonPoint(id);
    await _invalidateHorizon();
  }

  @override
  Future<ObservationSite?> get(String id, {bool includeDeleted = false}) =>
      PerformanceProbe.measureAsync(
        'db.observation_site.get',
        () => _dataSource.get(id, includeDeleted: includeDeleted),
        state: 'include_deleted=$includeDeleted',
      );

  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) =>
      PerformanceProbe.measureAsync(
        'db.observation_site.list',
        () => _dataSource.list(includeDeleted: includeDeleted),
        state: 'include_deleted=$includeDeleted',
      );

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
  ) async {
    await _dataSource.replaceBlockedRanges(siteId, ranges);
    await _invalidateHorizon();
  }

  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {
    await _dataSource.replaceHorizonPoints(siteId, points);
    await _invalidateHorizon();
  }

  @override
  Future<void> setFavorite(String id, bool favorite) =>
      _dataSource.setFavorite(id, favorite);

  @override
  Future<void> update(ObservationSite site) async {
    await _dataSource.update(site);
    await _invalidateSite();
  }

  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {
    await _dataSource.updateBlockedRange(range);
    await _invalidateHorizon();
  }

  @override
  Future<void> updateHorizonPoint(HorizonPoint point) async {
    await _dataSource.updateHorizonPoint(point);
    await _invalidateHorizon();
  }

  Future<void> _invalidateSite() =>
      contextInvalidator?.invalidate(
        ObservationContextChange.observationSite,
      ) ??
      Future.value();

  Future<void> _invalidateHorizon() =>
      contextInvalidator?.invalidate(ObservationContextChange.horizon) ??
      Future.value();
}
