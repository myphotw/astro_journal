import '../data/models/brightness_cell.dart';
import '../data/models/bortle_metadata.dart';
import '../data/models/observation_condition.dart';
import '../data/repositories/bortle_repository.dart';
import '../features/light_pollution_map/overlay/light_pollution_scale.dart';
import 'location_service.dart';
import 'observation_score_service.dart';

/// Computes the observation environment at the current or given location.
///
/// Uses [BortleRepository] for light-pollution lookup and derives SQM / Bortle
/// from World Atlas artificial zenith luminance (mcd/m²).
class ObservationConditionService {
  ObservationConditionService(
    this._locationService,
    this._bortleRepository,
  );

  final LocationService _locationService;
  final BortleRepository _bortleRepository;

  /// Returns observation conditions for the device's current GPS position.
  ///
  /// [preferLastKnown]는 광해지도 첫 진입처럼 UI 응답성이 중요할 때 사용한다.
  Future<ObservationCondition> getCurrentCondition({
    bool preferLastKnown = false,
  }) async {
    final location = await _locationService.getCurrentLocation(
      preferLastKnown: preferLastKnown,
    );
    return getConditionAt(location.latitude, location.longitude);
  }

  /// Returns observation conditions for the given WGS84 coordinates.
  Future<ObservationCondition> getConditionAt(
    double latitude,
    double longitude,
  ) async {
    final lookup = await _bortleRepository.lookup(latitude, longitude);
    final brightness = lookup?.brightness;
    final sqm = brightness != null
        ? LightPollutionScale.artificialMcdToSqmMag(brightness)
        : null;
    final bortle = brightness != null
        ? LightPollutionScale.artificialMcdToBortle(brightness)
        : null;

    return ObservationCondition(
      latitude: latitude,
      longitude: longitude,
      row: lookup?.row,
      col: lookup?.col,
      brightness: brightness,
      sqm: sqm,
      bortle: bortle,
      createdAt: DateTime.now(),
      observationScore: ObservationScoreService.computeSiteObservationScore(
        brightness: brightness,
      ),
    );
  }

  /// Returns brightness pixels visible within the given GPS bounds.
  Future<List<BrightnessCell>> getBrightnessInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    return _bortleRepository.getBrightnessInBounds(
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }

  /// Returns cached grid metadata from bortle.db.
  Future<BortleMetadata> getMetadata() => _bortleRepository.getMetadata();
}
