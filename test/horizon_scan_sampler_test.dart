import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_session.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_scan_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

OrientationSample _sample(
  double azimuth,
  int timestampNanos, {
  double pitch = 0,
}) => OrientationSample(
  sampledAt: DateTime.fromMicrosecondsSinceEpoch(timestampNanos ~/ 1000),
  sensorTimestampNanos: timestampNanos,
  azimuth: azimuth,
  pitch: pitch,
  roll: 0,
  accuracy: HorizonSensorAccuracy.good,
  trueNorthApplied: true,
);

HorizonScanSampler _sampler() => HorizonScanSampler(
  HorizonScanSession(
    id: 'scan',
    observationSiteId: 'site',
    startedAt: DateTime(2026),
    status: HorizonScanStatus.scanning,
  ),
);

void main() {
  group('heading unwrap', () {
    test('crosses north continuously in both directions', () {
      expect(HorizonScanSampler.unwrapDelta(359, 0), 1);
      expect(HorizonScanSampler.unwrapDelta(0, 1), 1);
      expect(HorizonScanSampler.unwrapDelta(1, 359), -2);
      expect(HorizonScanSampler.unwrapDelta(359, 358), -1);
    });
  });

  group('coverage and completion', () {
    test('completes a clockwise 360 scan with all 5 degree bins', () {
      final sampler = _sampler();
      for (var index = 0; index < HorizonScanSampler.totalBins; index++) {
        final sample = _sample(index * 5, index * 500000000);
        sampler.updateOrientation(sample);
        sampler.recordSample(sample);
      }
      expect(sampler.session.coveredBins, hasLength(72));
      expect(sampler.session.direction, HorizonScanDirection.clockwise);
      expect(sampler.session.status, HorizonScanStatus.completed);
      expect(sampler.isComplete, isTrue);
    });

    test('completes a counter-clockwise 360 scan', () {
      final sampler = _sampler();
      for (var index = 0; index < HorizonScanSampler.totalBins; index++) {
        final azimuth = HorizonScanSampler.normalizeAzimuth(-index * 5);
        final sample = _sample(azimuth, index * 500000000);
        sampler.updateOrientation(sample);
        sampler.recordSample(sample);
      }
      expect(sampler.session.direction, HorizonScanDirection.counterClockwise);
      expect(sampler.isComplete, isTrue);
    });

    test('does not complete partial or duplicate scans', () {
      final sampler = _sampler();
      for (var index = 0; index < 40; index++) {
        final sample = _sample(index * 5, index * 500000000);
        sampler.updateOrientation(sample);
        sampler.recordSample(sample);
        sampler.recordSample(sample);
      }
      expect(sampler.session.coveredBins, hasLength(40));
      expect(sampler.session.samples, hasLength(40));
      expect(sampler.isComplete, isFalse);
      expect(sampler.session.missingBins(72), hasLength(32));
    });

    test('permits a short reverse without falsely adding rotation', () {
      final sampler = _sampler();
      for (final entry in <(double, int)>[
        (0, 0),
        (10, 1000000000),
        (5, 1500000000),
        (15, 2500000000),
      ]) {
        sampler.updateOrientation(_sample(entry.$1, entry.$2));
      }
      expect(sampler.session.cumulativeRotation, 15);
      expect(sampler.session.direction, HorizonScanDirection.clockwise);
    });
  });

  group('guides', () {
    test('classifies steady, too fast, and stationary speed', () {
      final sampler = _sampler();
      sampler.updateOrientation(_sample(0, 0));
      sampler.updateOrientation(_sample(5, 500000000));
      expect(sampler.session.currentSpeed, 10);
      expect(sampler.session.speedGuide, HorizonSpeedGuide.steady);

      sampler.updateOrientation(_sample(10, 600000000));
      expect(sampler.session.currentSpeed, 50);
      expect(sampler.session.speedGuide, HorizonSpeedGuide.tooFast);

      sampler.updateOrientation(_sample(10, 1100000000));
      expect(sampler.session.currentSpeed, 0);
      expect(sampler.session.speedGuide, HorizonSpeedGuide.steady);
    });

    test('guides camera pitch up and down', () {
      final sampler = _sampler();
      sampler.updateOrientation(_sample(0, 0, pitch: -20));
      expect(sampler.session.pitchGuide, HorizonPitchGuide.tiltUp);
      sampler.updateOrientation(_sample(1, 100000000, pitch: 20));
      expect(sampler.session.pitchGuide, HorizonPitchGuide.tiltDown);
      sampler.updateOrientation(_sample(2, 200000000, pitch: 3));
      expect(sampler.session.pitchGuide, HorizonPitchGuide.level);
    });
  });
}
