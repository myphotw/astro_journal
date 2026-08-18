import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/services/observation_site_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ObservationSite site({
    String name = 'Site',
    double latitude = 37,
    double longitude = 127,
    double minAltitude = 20,
    double? maxAltitude,
    List<HorizonPoint> points = const [],
    List<BlockedAzimuthRange> ranges = const [],
  }) {
    return ObservationSite(
      id: 'site',
      name: name,
      latitude: latitude,
      longitude: longitude,
      defaultMinAltitude: minAltitude,
      defaultMaxAltitude: maxAltitude,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      horizonPoints: points,
      blockedAzimuthRanges: ranges,
    );
  }

  test('rejects empty name and invalid coordinates', () {
    expect(
      () => ObservationSiteValidator.validate(site(name: '')),
      throwsArgumentError,
    );
    expect(
      () => ObservationSiteValidator.validate(site(latitude: 91)),
      throwsArgumentError,
    );
    expect(
      () => ObservationSiteValidator.validate(site(longitude: -181)),
      throwsArgumentError,
    );
  });

  test('rejects invalid altitude and azimuth values', () {
    expect(
      () => ObservationSiteValidator.validate(
        site(minAltitude: 70, maxAltitude: 60),
      ),
      throwsArgumentError,
    );
    for (final azimuth in [-1.0, 360.0]) {
      expect(
        () => ObservationSiteValidator.validateHorizonPoint(
          HorizonPoint(
            id: 'p',
            observationSiteId: 'site',
            azimuth: azimuth,
            minAltitude: 0,
          ),
        ),
        throwsArgumentError,
      );
    }
  });

  test('rejects duplicate horizon azimuth', () {
    const points = [
      HorizonPoint(
        id: 'p1',
        observationSiteId: 'site',
        azimuth: 120,
        minAltitude: 20,
      ),
      HorizonPoint(
        id: 'p2',
        observationSiteId: 'site',
        azimuth: 120,
        minAltitude: 25,
      ),
    ];
    expect(
      () => ObservationSiteValidator.validate(site(points: points)),
      throwsArgumentError,
    );
  });

  test('allows circular blocked range 350 to 20', () {
    const range = BlockedAzimuthRange(
      id: 'r',
      observationSiteId: 'site',
      startAzimuth: 350,
      endAzimuth: 20,
    );
    expect(
      () => ObservationSiteValidator.validate(site(ranges: const [range])),
      returnsNormally,
    );
    expect(range.contains(0), isTrue);
  });
}
