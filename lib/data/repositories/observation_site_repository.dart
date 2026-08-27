import '../models/blocked_azimuth_range.dart';
import '../models/horizon_point.dart';
import '../models/observation_site.dart';

abstract class ObservationSiteRepository {
  Future<List<ObservationSite>> list({bool includeDeleted = false});
  Future<ObservationSite?> get(String id, {bool includeDeleted = false});
  Future<void> create(ObservationSite site);
  Future<void> createFavorite(ObservationSite site);
  Future<void> update(ObservationSite site);
  Future<void> delete(String id, {bool hard = false});
  Future<void> setFavorite(String id, bool favorite);
  Future<void> markLastUsed(String id, DateTime usedAt);

  Future<List<HorizonPoint>> listHorizonPoints(String siteId);
  Future<void> addHorizonPoint(HorizonPoint point);
  Future<void> updateHorizonPoint(HorizonPoint point);
  Future<void> deleteHorizonPoint(String id);
  Future<void> replaceHorizonPoints(String siteId, List<HorizonPoint> points);

  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId);
  Future<void> addBlockedRange(BlockedAzimuthRange range);
  Future<void> updateBlockedRange(BlockedAzimuthRange range);
  Future<void> deleteBlockedRange(String id);
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  );
}
