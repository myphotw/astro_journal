import 'package:astro_journal/features/horizon_scan/models/horizon_measurement_result.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_measurement_profile_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = HorizonMeasurementProfileBuilder();

  List<HorizonBoundaryMeasurement> samples(
    List<(double, double)> values,
  ) => [
    for (final value in values)
      HorizonBoundaryMeasurement(azimuth: value.$1, altitude: value.$2),
  ];

  HorizonMeasurementResult build({
    List<(double, double)> left = const [],
    List<(double, double)> right = const [],
    List<(double, double)> upper = const [],
    List<(double, double)> lower = const [],
  }) => builder.build(
    observationSiteId: 'site',
    leftMeasurements: samples(left),
    rightMeasurements: samples(right),
    upperMeasurements: samples(upper),
    lowerMeasurements: samples(lower),
  );

  double minAt(HorizonMeasurementResult result, double azimuth) => result.points
      .singleWhere((point) => point.azimuth == azimuth)
      .minAltitude;

  double maxAt(HorizonMeasurementResult result, double azimuth) => result.points
      .singleWhere((point) => point.azimuth == azimuth)
      .maxAltitude!;

  test('multi-point lower boundary is interpolated by direction', () {
    final result = build(
      left: const [(120, 30)],
      right: const [(215, 30)],
      lower: const [(120, 20), (150, 30), (180, 50), (215, 22)],
    );

    expect(result.points, hasLength(36));
    expect(minAt(result, 120), 20);
    expect(minAt(result, 150), 30);
    expect(minAt(result, 180), 50);
    expect(minAt(result, 180), greaterThan(minAt(result, 140)));
  });

  test('multi-point upper boundary is interpolated by direction', () {
    final result = build(
      left: const [(120, 30)],
      right: const [(215, 30)],
      upper: const [(120, 64), (170, 65), (215, 62)],
    );

    expect(maxAt(result, 120), 64);
    expect(maxAt(result, 170), 65);
    expect(maxAt(result, 190), closeTo(63.67, 0.01));
  });

  test('single upper and lower samples are held across the available range', () {
    final result = build(
      left: const [(120, 20)],
      right: const [(215, 20)],
      upper: const [(170, 65)],
      lower: const [(180, 50)],
    );

    for (final azimuth in const [120.0, 150.0, 180.0, 210.0]) {
      expect(minAt(result, azimuth), 50);
      expect(maxAt(result, azimuth), 65);
    }
  });

  test('left and right boundaries create the outside blocked range', () {
    final result = build(
      left: const [(120, 20)],
      right: const [(215, 20)],
    );

    expect(result.mode, HorizonMeasurementMode.limited);
    expect(result.startAzimuth, 120);
    expect(result.endAzimuth, 215);
    expect(result.blockedRanges.single.startAzimuth, 216);
    expect(result.blockedRanges.single.endAzimuth, 119);
    expect(result.blockedRanges.single.contains(80), isTrue);
    expect(result.blockedRanges.single.contains(150), isFalse);
  });

  test('multiple side samples use their circular mean as representative azimuth', () {
    final result = build(
      left: const [(358, 20), (2, 30)],
      right: const [(58, 20), (62, 30)],
    );

    expect(result.startAzimuth, 0);
    expect(result.endAzimuth, 60);
  });

  test('wrap-around left and right boundaries keep north available', () {
    final result = build(
      left: const [(300, 20)],
      right: const [(60, 20)],
    );

    final blocked = result.blockedRanges.single;
    expect(blocked.startAzimuth, 61);
    expect(blocked.endAzimuth, 299);
    expect(blocked.contains(180), isTrue);
    expect(blocked.contains(330), isFalse);
    expect(blocked.contains(30), isFalse);
  });

  test('outdoor horizon is inferred and circularly interpolated', () {
    final result = build(
      lower: const [
        (0, 10),
        (90, 20),
        (180, 5),
        (270, 15),
      ],
    );

    expect(result.mode, HorizonMeasurementMode.fullSky);
    expect(result.blockedRanges, isEmpty);
    expect(maxAt(result, 90), 90);
    expect(minAt(result, 350), closeTo(10.56, 0.01));
    expect(minAt(result, 10), closeTo(11.11, 0.01));
  });

  test('no measured boundaries creates a fully open profile', () {
    final result = build();

    expect(result.mode, HorizonMeasurementMode.fullSky);
    expect(result.blockedRanges, isEmpty);
    expect(
      result.points.every(
        (point) => point.minAltitude == 0 && point.maxAltitude == 90,
      ),
      isTrue,
    );
  });

  test('missing upper boundary defaults every maximum to 90 degrees', () {
    final result = build(lower: const [(0, 10), (180, 20)]);

    expect(result.points.every((point) => point.maxAltitude == 90), isTrue);
  });

  test('one-sided azimuth boundary is rejected instead of being guessed', () {
    expect(
      () => build(left: const [(120, 20)]),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => build(right: const [(215, 20)]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('limited interpolation holds nearest sample through both endpoints', () {
    final result = build(
      left: const [(120, 20)],
      right: const [(215, 20)],
      upper: const [(130, 64), (200, 62)],
      lower: const [(130, 22), (200, 30)],
    );

    expect(minAt(result, 120), 22);
    expect(minAt(result, 210), 30);
    expect(maxAt(result, 120), 64);
    expect(maxAt(result, 210), 62);
  });

  test('circular interpolation has no discontinuity around north', () {
    final result = build(lower: const [(350, 10), (20, 12)]);

    expect(minAt(result, 350), 10);
    expect(minAt(result, 0), closeTo(10.67, 0.01));
    expect(minAt(result, 10), closeTo(11.33, 0.01));
    expect(minAt(result, 20), 12);
  });
}
