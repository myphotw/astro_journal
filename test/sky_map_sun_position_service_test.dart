import 'package:astro_journal/services/sky_map_sun_position_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SkyMapSunPositionService', () {
    test('equinox sun is overhead near noon at the equator', () {
      final altitude = SkyMapSunPositionService.altitudeDeg(
        time: DateTime.utc(2026, 3, 20, 12),
        latitudeDeg: 0,
        longitudeDeg: 0,
      );

      expect(altitude, greaterThan(85));
    });

    test('equinox sun is below the horizon near midnight at the equator', () {
      final altitude = SkyMapSunPositionService.altitudeDeg(
        time: DateTime.utc(2026, 3, 20),
        latitudeDeg: 0,
        longitudeDeg: 0,
      );

      expect(altitude, lessThan(-85));
    });

    test('solar declination follows the solstice hemisphere', () {
      final june = SkyMapSunPositionService.equatorialCoordinates(
        DateTime.utc(2026, 6, 21, 12),
      );
      final december = SkyMapSunPositionService.equatorialCoordinates(
        DateTime.utc(2026, 12, 21, 12),
      );

      expect(june.decDeg, closeTo(23.44, 0.3));
      expect(december.decDeg, closeTo(-23.44, 0.3));
    });

    test('horizontal position exposes the solar azimuth used by the sky', () {
      final position = SkyMapSunPositionService.position(
        time: DateTime.utc(2026, 4, 10, 9),
        latitudeDeg: 37.5,
        longitudeDeg: 127,
      );
      final altitude = SkyMapSunPositionService.altitudeDeg(
        time: DateTime.utc(2026, 4, 10, 9),
        latitudeDeg: 37.5,
        longitudeDeg: 127,
      );

      expect(position.azimuth, inInclusiveRange(0, 360));
      expect(position.altitude, closeTo(altitude, 1e-10));
    });
  });
}
