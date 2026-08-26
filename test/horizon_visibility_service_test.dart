import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/site_horizon_profile.dart';
import 'package:astro_journal/services/horizon_visibility_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = HorizonVisibilityService();

  HorizonPoint point(double azimuth, double altitude, {String? id}) =>
      HorizonPoint(
        id: id ?? 'p-$azimuth',
        observationSiteId: 'site',
        azimuth: azimuth,
        minAltitude: altitude,
      );

  test('no horizon falls back to unrestricted zero degrees', () {
    const profile = SiteHorizonProfile();
    expect(service.minimumVisibleAltitude(profile, 123), 0);
    expect(
      service.isVisible(profile: profile, azimuth: 123, altitude: 0),
      isTrue,
    );
  });

  test('returns exact point and linearly interpolates between points', () {
    final profile = SiteHorizonProfile(points: [point(90, 20), point(180, 40)]);
    expect(service.minimumVisibleAltitude(profile, 90), 20);
    expect(service.minimumVisibleAltitude(profile, 135), closeTo(30, 1e-9));
  });

  test('interpolates continuously across zero and 360 boundary', () {
    final profile = SiteHorizonProfile(points: [point(45, 10), point(315, 30)]);
    expect(service.minimumVisibleAltitude(profile, 0), closeTo(20, 1e-9));
    expect(service.minimumVisibleAltitude(profile, 360), closeTo(20, 1e-9));
  });

  test('clamps imported altitude values to physical visible range', () {
    final low = SiteHorizonProfile(points: [point(0, -20)]);
    final high = SiteHorizonProfile(points: [point(0, 120)]);
    expect(service.minimumVisibleAltitude(low, 0), 0);
    expect(service.minimumVisibleAltitude(high, 0), 90);
  });

  test('duplicate azimuth deterministically uses the last sample', () {
    final profile = SiteHorizonProfile(
      points: [
        point(90, 10, id: 'first'),
        point(90, 25, id: 'last'),
      ],
    );
    expect(service.minimumVisibleAltitude(profile, 90), 25);
  });

  test('blocked range crossing north is never visible', () {
    final profile = SiteHorizonProfile(
      blockedRanges: const [
        BlockedAzimuthRange(
          id: 'blocked',
          observationSiteId: 'site',
          startAzimuth: 350,
          endAzimuth: 20,
        ),
      ],
    );
    expect(
      service.isVisible(profile: profile, azimuth: 0, altitude: 90),
      isFalse,
    );
    expect(
      service.isVisible(profile: profile, azimuth: 180, altitude: 0),
      isTrue,
    );
  });
}
