import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CelestialPositionService RA parsing', () {
    test('preserves minute-only coordinates and parses seconds', () {
      expect(CelestialPositionService.parseRaHours('00h 00m'), 0);
      expect(CelestialPositionService.parseRaHours('00h 00m 00s'), 0);
      expect(
        CelestialPositionService.parseRaHours('05h 35m'),
        closeTo(5 + 35 / 60, 1e-12),
      );
      expect(
        CelestialPositionService.parseRaHours('05h 35m 17s'),
        closeTo(5 + 35 / 60 + 17 / 3600, 1e-12),
      );
      expect(
        CelestialPositionService.parseRaHours('12h30m30.5s'),
        closeTo(12 + 30 / 60 + 30.5 / 3600, 1e-12),
      );
      expect(
        CelestialPositionService.parseRaHours('23h 59m 59s'),
        closeTo(23 + 59 / 60 + 59 / 3600, 1e-12),
      );
    });

    test('rejects missing, malformed, trailing, and out-of-range values', () {
      for (final value in <String?>[
        null,
        '-',
        '',
        '   ',
        'abc',
        '24h 01m',
        '12h 60m',
        '12h 30m 60s',
        '12h 30m garbage',
      ]) {
        expect(
          CelestialPositionService.parseRaHours(value),
          isNull,
          reason: '$value must not become RA 0h',
        );
      }
    });

    test('C44 production coordinate retains fractional seconds', () {
      expect(
        CelestialPositionService.parseRaHours('23h 04m 56.6s'),
        closeTo(23 + 4 / 60 + 56.6 / 3600, 1e-12),
      );
    });
  });

  group('CelestialPositionService Dec parsing', () {
    test('preserves minute-only coordinates and parses seconds', () {
      expect(CelestialPositionService.parseDecDeg('+00° 00′'), 0);
      expect(CelestialPositionService.parseDecDeg('-00° 00′'), 0);
      expect(CelestialPositionService.parseDecDeg('+40° 00′'), 40);
      expect(
        CelestialPositionService.parseDecDeg('-37° 08′'),
        closeTo(-(37 + 8 / 60), 1e-12),
      );
      expect(
        CelestialPositionService.parseDecDeg('-37° 08′ 30″'),
        closeTo(-(37 + 8 / 60 + 30 / 3600), 1e-12),
      );
      expect(
        CelestialPositionService.parseDecDeg('+89° 59′ 59″'),
        closeTo(89 + 59 / 60 + 59 / 3600, 1e-12),
      );
      expect(
        CelestialPositionService.parseDecDeg('-89° 59′ 59″'),
        closeTo(-(89 + 59 / 60 + 59 / 3600), 1e-12),
      );
      expect(CelestialPositionService.parseDecDeg('+90° 00′ 00″'), 90);
      expect(CelestialPositionService.parseDecDeg('-90° 00′ 00″'), -90);
    });

    test('supports existing d/m/s and production ASCII quote formats', () {
      expect(
        CelestialPositionService.parseDecDeg('-05d23m28s'),
        closeTo(-(5 + 23 / 60 + 28 / 3600), 1e-12),
      );
      expect(
        CelestialPositionService.parseDecDeg('+12° 19\' 22.4"'),
        closeTo(12 + 19 / 60 + 22.4 / 3600, 1e-12),
      );
    });

    test('rejects missing, malformed, trailing, and out-of-range values', () {
      for (final value in <String?>[
        null,
        '-',
        '',
        '   ',
        'abc',
        '+91° 00′',
        '+90° 01′',
        '-90° 00′ 01″',
        '+40° 60′',
        '+40° 00′ 60″',
        '+40° 00′ garbage',
      ]) {
        expect(
          CelestialPositionService.parseDecDeg(value),
          isNull,
          reason: '$value must not become Dec 0°',
        );
      }
    });
  });

  test('valid zero coordinate is distinct from invalid input', () {
    expect(CelestialPositionService.parseRaHours('00h 00m 00s'), isNotNull);
    expect(CelestialPositionService.parseDecDeg('+00° 00′ 00″'), isNotNull);
    expect(CelestialPositionService.parseRaHours('-'), isNull);
    expect(CelestialPositionService.parseDecDeg('-'), isNull);
  });
}
