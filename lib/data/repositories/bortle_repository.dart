import '../models/brightness_cell.dart';
import '../models/bortle_lookup_result.dart';
import '../models/bortle_metadata.dart';

abstract class BortleRepository {
  Future<BortleMetadata> getMetadata();
  Future<double?> getBrightness(double latitude, double longitude);
  Future<BortleLookupResult?> lookup(double latitude, double longitude);
  Future<List<BrightnessCell>> getBrightnessInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  });
}
