import 'dart:typed_data';

import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_session.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_scan_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HorizonFrameReference frameWithBoundary(int boundaryRow) {
    const width = 24;
    const height = 20;
    final bytes = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        bytes[y * width + x] = y < boundaryRow ? 220 : 30;
      }
    }
    return HorizonFrameReference(
      capturedAt: DateTime(2026),
      width: width,
      height: height,
      lumaBytes: bytes,
    );
  }

  test('camera frames become a smoothed 360-degree Horizon profile', () {
    final session =
        HorizonScanSession(
            id: 'scan-1',
            observationSiteId: 'site-1',
            startedAt: DateTime(2026),
            status: HorizonScanStatus.completed,
          )
          ..cameraInformation = const HorizonScanCameraInformation(
            cameraName: 'test',
            previewWidth: 24,
            previewHeight: 20,
            sensorOrientation: 90,
            horizontalFov: 60,
            verticalFov: 40,
            intrinsicsSource: 'estimated',
            intrinsicsConfidence: 'medium',
          );

    for (var index = 0; index < 72; index++) {
      session.samples.add(
        HorizonScanSample(
          timestamp: DateTime(2026).add(Duration(milliseconds: index * 100)),
          sensorTimestampNanos: index * 100000000,
          azimuth: index * 5,
          pitch: 5,
          roll: 0,
          coverageBin: index,
          sensorAccuracy: HorizonSensorAccuracy.good,
          trueNorthApplied: true,
          frame: frameWithBoundary(10),
        ),
      );
    }

    final points = const HorizonScanProcessor().process(session);

    expect(points, hasLength(36));
    expect(
      points.map((point) => point.azimuth),
      orderedEquals(<double>[
        for (var azimuth = 0; azimuth < 360; azimuth += 10) azimuth.toDouble(),
      ]),
    );
    expect(
      points.every((point) => point.source == HorizonDataSource.cameraScan),
      isTrue,
    );
    expect(points.every((point) => point.minAltitude >= 0), isTrue);
    expect(points.first.minAltitude, closeTo(4, 2));
  });

  test('rejects frames without a detectable boundary', () {
    final session = HorizonScanSession(
      id: 'scan-2',
      observationSiteId: 'site-1',
      startedAt: DateTime(2026),
    );
    session.samples.add(
      HorizonScanSample(
        timestamp: DateTime(2026),
        sensorTimestampNanos: 0,
        azimuth: 0,
        pitch: 0,
        roll: 0,
        coverageBin: 0,
        sensorAccuracy: HorizonSensorAccuracy.good,
        trueNorthApplied: true,
        frame: HorizonFrameReference(
          capturedAt: DateTime(2026),
          width: 10,
          height: 10,
          lumaBytes: Uint8List.fromList(List<int>.filled(100, 100)),
        ),
      ),
    );

    expect(const HorizonScanProcessor().process(session), isEmpty);
  });
}
