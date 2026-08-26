import 'package:astro_journal/data/models/bortle_lookup_result.dart';
import 'package:astro_journal/data/repositories/bortle_repository.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_scale.dart';
import 'package:astro_journal/services/location_service.dart';
import 'package:astro_journal/services/observation_condition_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _BortleRepository implements BortleRepository {
  @override
  Future<BortleLookupResult?> lookup(double latitude, double longitude) async =>
      BortleLookupResult(
        latitude: latitude,
        longitude: longitude,
        row: 12,
        col: 34,
        brightness: 1.5,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'coordinates derive Bortle and SQM from the local atlas lookup',
    () async {
      final condition = await ObservationConditionService(
        LocationService(),
        _BortleRepository(),
      ).getConditionAt(37.5, 127);

      expect(condition.latitude, 37.5);
      expect(condition.longitude, 127);
      expect(condition.bortle, LightPollutionScale.artificialMcdToBortle(1.5));
      expect(condition.sqm, LightPollutionScale.artificialMcdToSqmMag(1.5));
    },
  );
}
