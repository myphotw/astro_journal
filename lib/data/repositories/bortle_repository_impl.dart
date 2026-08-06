import '../../services/bortle_database_service.dart';
import '../models/brightness_cell.dart';
import '../models/bortle_lookup_result.dart';
import '../models/bortle_metadata.dart';
import 'bortle_repository.dart';

class BortleRepositoryImpl implements BortleRepository {
  @override
  Future<BortleMetadata> getMetadata() => BortleDatabaseService.getMetadata();

  @override
  Future<double?> getBrightness(double latitude, double longitude) {
    return BortleDatabaseService.getBrightness(latitude, longitude);
  }

  @override
  Future<BortleLookupResult?> lookup(
    double latitude,
    double longitude,
  ) async {
    final metadata = await getMetadata();
    final grid = metadata.latLonToRowCol(latitude, longitude);
    if (!metadata.isInBounds(grid.row, grid.col)) {
      return null;
    }

    final brightness = await getBrightness(latitude, longitude);
    if (brightness == null) {
      return null;
    }

    return BortleLookupResult(
      latitude: latitude,
      longitude: longitude,
      row: grid.row,
      col: grid.col,
      brightness: brightness,
    );
  }

  @override
  Future<List<BrightnessCell>> getBrightnessInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    return BortleDatabaseService.getBrightnessInBounds(
      south: south,
      west: west,
      north: north,
      east: east,
    );
  }
}
