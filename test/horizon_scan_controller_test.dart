import 'dart:async';

import 'package:astro_journal/features/horizon_scan/controller/horizon_scan_controller.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_session.dart';
import 'package:astro_journal/features/horizon_scan/services/camera_intrinsics_service.dart';
import 'package:astro_journal/features/horizon_scan/services/device_orientation_service.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_camera_service.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_scan_processor.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrientationService implements DeviceOrientationService {
  final controller = StreamController<OrientationSample>.broadcast();
  int starts = 0;
  int stops = 0;
  double? latitude;
  double? longitude;

  @override
  Stream<OrientationSample> get samples => controller.stream;

  @override
  Future<void> start({double? latitude, double? longitude}) async {
    starts++;
    this.latitude = latitude;
    this.longitude = longitude;
  }

  @override
  Future<void> stop() async => stops++;
}

class _FakeCameraService implements HorizonCameraService {
  _FakeCameraService({this.permission = HorizonCameraPermissionState.granted});

  final HorizonCameraPermissionState permission;
  final CameraController _controller = CameraController(
    const CameraDescription(
      name: 'fake-wide',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
      lensType: CameraLensType.wide,
    ),
    ResolutionPreset.high,
  );
  int initializations = 0;
  int streamStarts = 0;
  int pauses = 0;

  @override
  CameraController get cameraController => _controller;

  @override
  Future<HorizonCameraPermissionState> requestPermission() async => permission;

  @override
  Future<void> initialize() async => initializations++;

  @override
  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    streamStarts++;
  }

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> dispose() async => pauses++;
}

class _FakeIntrinsicsService implements CameraIntrinsicsService {
  @override
  Future<CameraIntrinsics> resolve(CameraController controller) async =>
      const CameraIntrinsics(
        horizontalFov: 65,
        verticalFov: 50,
        source: CameraIntrinsicsSource.estimated,
        confidence: CameraIntrinsicsConfidence.low,
        previewWidth: 1280,
        previewHeight: 720,
        sensorOrientation: 90,
        cameraName: 'fake-wide',
      );
}

class _FakeProcessor extends HorizonScanProcessor {
  _FakeProcessor(this.camera);

  final _FakeCameraService camera;
  int calls = 0;
  int? pausesWhenProcessed;

  @override
  List<HorizonPoint> process(HorizonScanSession session) {
    calls++;
    pausesWhenProcessed = camera.pauses;
    return const [
      HorizonPoint(
        id: 'point',
        observationSiteId: 'site',
        azimuth: 0,
        minAltitude: 12,
        sortOrder: 0,
        source: HorizonDataSource.cameraScan,
      ),
    ];
  }
}

HorizonScanController _controller(
  _FakeOrientationService orientation,
  _FakeCameraService camera, {
  HorizonScanProcessor? processor,
}) => HorizonScanController(
  observationSiteId: 'site',
  observationSiteName: 'Site',
  latitude: 37.5,
  longitude: 127,
  orientationService: orientation,
  cameraService: camera,
  intrinsicsService: _FakeIntrinsicsService(),
  processor: processor ?? const HorizonScanProcessor(),
);

void main() {
  test('starts, pauses, resumes, cancels, and releases resources', () async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService();
    final controller = _controller(orientation, camera);

    await controller.initialize();
    expect(controller.session.status, HorizonScanStatus.scanning);
    expect(camera.initializations, 1);
    expect(camera.streamStarts, 1);
    expect(orientation.starts, 1);
    expect(orientation.latitude, 37.5);
    expect(orientation.longitude, 127);

    await controller.pause();
    expect(controller.session.status, HorizonScanStatus.paused);
    expect(camera.pauses, 1);

    await controller.resume();
    expect(controller.session.status, HorizonScanStatus.scanning);
    expect(camera.initializations, 2);
    expect(orientation.starts, 2);

    await controller.cancel();
    expect(controller.session.status, HorizonScanStatus.cancelled);
    expect(controller.session.samples, isEmpty);
    controller.dispose();
    await orientation.controller.close();
  });

  test('permission denial becomes a recoverable error', () async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService(
      permission: HorizonCameraPermissionState.denied,
    );
    final controller = _controller(orientation, camera);

    await controller.initialize();
    expect(controller.session.status, HorizonScanStatus.error);
    expect(controller.errorMessage, contains('카메라 권한'));
    expect(camera.initializations, 0);
    controller.dispose();
    await orientation.controller.close();
  });

  test(
    'records orientation samples without creating HorizonPoint data',
    () async {
      final orientation = _FakeOrientationService();
      final camera = _FakeCameraService();
      final controller = _controller(orientation, camera);
      await controller.initialize();

      controller.recordSampleForTest(
        OrientationSample(
          sampledAt: DateTime(2026),
          sensorTimestampNanos: 0,
          azimuth: 5,
          pitch: 2,
          roll: 1,
          accuracy: HorizonSensorAccuracy.good,
          trueNorthApplied: true,
        ),
      );
      expect(controller.session.samples, hasLength(1));
      expect(controller.session.samples.single.coverageBin, 1);
      expect(controller.session.cameraInformation?.previewWidth, 1280);
      controller.dispose();
      await orientation.controller.close();
    },
  );

  test('full coverage completes exactly once after resources stop', () async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService();
    final processor = _FakeProcessor(camera);
    final controller = _controller(orientation, camera, processor: processor);
    final transitions = <HorizonScanStatus>[];
    controller.addListener(() => transitions.add(controller.session.status));
    await controller.initialize();

    for (var index = 0; index < 72; index++) {
      controller.recordSampleForTest(
        OrientationSample(
          sampledAt: DateTime(2026),
          sensorTimestampNanos: index * 500000000,
          azimuth: index * 5,
          pitch: 0,
          roll: 0,
          accuracy: HorizonSensorAccuracy.good,
          trueNorthApplied: true,
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(transitions, contains(HorizonScanStatus.processing));
    expect(controller.session.status, HorizonScanStatus.completed);
    expect(controller.horizonPoints, hasLength(1));
    expect(processor.calls, 1);
    expect(processor.pausesWhenProcessed, 1);
    expect(camera.pauses, 1);
    expect(orientation.stops, 1);

    controller.recordSampleForTest(
      OrientationSample(
        sampledAt: DateTime(2026),
        sensorTimestampNanos: 40000000000,
        azimuth: 0,
        pitch: 0,
        roll: 0,
        accuracy: HorizonSensorAccuracy.good,
        trueNorthApplied: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(processor.calls, 1);

    controller.dispose();
    await orientation.controller.close();
  });

  test('retry discards the prior scan and starts clean resources', () async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService();
    final processor = _FakeProcessor(camera);
    final controller = _controller(orientation, camera, processor: processor);
    await controller.initialize();
    final firstSessionId = controller.session.id;
    for (var index = 0; index < 72; index++) {
      controller.recordSampleForTest(
        OrientationSample(
          sampledAt: DateTime(2026),
          sensorTimestampNanos: index * 500000000,
          azimuth: index * 5,
          pitch: 0,
          roll: 0,
          accuracy: HorizonSensorAccuracy.good,
          trueNorthApplied: true,
        ),
      );
    }
    await controller.waitForCompletion();
    expect(controller.session.status, HorizonScanStatus.completed);

    await controller.restart();

    expect(controller.session.id, isNot(firstSessionId));
    expect(controller.session.status, HorizonScanStatus.scanning);
    expect(controller.session.samples, isEmpty);
    expect(controller.horizonPoints, isEmpty);
    expect(camera.initializations, 2);
    expect(camera.streamStarts, 2);
    expect(orientation.starts, 2);

    await controller.close();
    final sampleCount = controller.session.sampleCount;
    orientation.controller.add(
      OrientationSample(
        sampledAt: DateTime(2026),
        sensorTimestampNanos: 50000000000,
        azimuth: 180,
        pitch: 0,
        roll: 0,
        accuracy: HorizonSensorAccuracy.good,
        trueNorthApplied: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.session.sampleCount, sampleCount);

    controller.dispose();
    await orientation.controller.close();
  });
}
