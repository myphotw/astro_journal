import 'dart:async';

import 'package:astro_journal/features/horizon_scan/controller/horizon_measurement_controller.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/services/device_orientation_service.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_camera_service.dart';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrientationService implements DeviceOrientationService {
  final streamController = StreamController<OrientationSample>.broadcast();

  @override
  Stream<OrientationSample> get samples => streamController.stream;

  @override
  Future<void> start({double? latitude, double? longitude}) async {}

  @override
  Future<void> stop() async {}
}

class _FakeCameraService implements HorizonCameraService {
  final controller = CameraController(
    const CameraDescription(
      name: 'fake',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    ResolutionPreset.medium,
  );
  int imageStreamStarts = 0;

  @override
  CameraController get cameraController => controller;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<HorizonCameraPermissionState> requestPermission() async =>
      HorizonCameraPermissionState.granted;

  @override
  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async => imageStreamStarts++;

  @override
  Future<void> dispose() async {}
}

OrientationSample _sample(double azimuth, double altitude) => OrientationSample(
  sampledAt: DateTime(2026),
  sensorTimestampNanos: 0,
  azimuth: azimuth,
  pitch: altitude,
  roll: 0,
  accuracy: HorizonSensorAccuracy.good,
  trueNorthApplied: true,
);

void main() {
  late _FakeOrientationService orientation;
  late _FakeCameraService camera;
  late HorizonMeasurementController controller;

  setUp(() {
    orientation = _FakeOrientationService();
    camera = _FakeCameraService();
    controller = HorizonMeasurementController(
      observationSiteId: 'site',
      latitude: 37.5,
      longitude: 127,
      orientationService: orientation,
      cameraService: camera,
    );
  });

  tearDown(() async {
    await controller.close();
    controller.dispose();
    await orientation.streamController.close();
  });

  test('controller collects each boundary and produces a result', () async {
    expect(controller.status, HorizonMeasurementStatus.introduction);
    await controller.startMeasurement();
    expect(controller.step, HorizonBoundaryStep.left);
    expect(camera.imageStreamStarts, 0);

    controller.handleOrientationSample(_sample(120, 30));
    controller.addCurrentPoint();
    await controller.nextStep();
    expect(controller.step, HorizonBoundaryStep.right);

    controller.handleOrientationSample(_sample(215, 30));
    controller.addCurrentPoint();
    await controller.nextStep();
    expect(controller.step, HorizonBoundaryStep.upper);

    controller.handleOrientationSample(_sample(170, 65));
    controller.addCurrentPoint();
    await controller.nextStep();
    expect(controller.step, HorizonBoundaryStep.lower);

    controller.handleOrientationSample(_sample(180, 50));
    controller.addCurrentPoint();
    expect(controller.status, HorizonMeasurementStatus.measuring);
    expect(controller.step, HorizonBoundaryStep.lower);
    await controller.nextStep();

    expect(controller.status, HorizonMeasurementStatus.summary);
    expect(controller.result?.points, hasLength(36));
    expect(controller.result?.upperMeasurements, hasLength(1));
    expect(controller.result?.lowerMeasurements, hasLength(1));
    expect(
      controller.result?.points.every(
        (point) => point.minAltitude == 50 && point.maxAltitude == 65,
      ),
      isTrue,
    );
  });

  test('current step supports individual, last, and full deletion', () async {
    await controller.startMeasurement();
    for (final value in const [(120.0, 20.0), (130.0, 25.0), (140.0, 30.0)]) {
      controller.handleOrientationSample(_sample(value.$1, value.$2));
      controller.addCurrentPoint();
    }
    expect(controller.currentMeasurements, hasLength(3));

    controller.deletePoint(1);
    expect(controller.currentMeasurements, hasLength(2));
    controller.deleteLastPoint();
    expect(controller.currentMeasurements, hasLength(1));
    controller.clearCurrentPoints();
    expect(controller.currentMeasurements, isEmpty);
  });

  test('one-sided left and right boundary requires confirmation', () async {
    await controller.startMeasurement();
    controller.handleOrientationSample(_sample(120, 20));
    controller.addCurrentPoint();
    await controller.nextStep();
    await controller.nextStep();

    expect(controller.step, HorizonBoundaryStep.right);
    expect(controller.errorMessage, contains('모두 측정하거나 모두 건너뛰어'));
    controller.previousStep();
    expect(controller.step, HorizonBoundaryStep.left);
  });

  test('all empty steps produce a fully open result', () async {
    await controller.startMeasurement();
    await controller.nextStep();
    await controller.nextStep();
    await controller.nextStep();
    await controller.nextStep();

    expect(controller.status, HorizonMeasurementStatus.summary);
    expect(controller.result?.blockedRanges, isEmpty);
    expect(
      controller.result?.points.every(
        (point) => point.minAltitude == 0 && point.maxAltitude == 90,
      ),
      isTrue,
    );
  });

  test('keeps the selected sensor value raw while the profile clamps it', () async {
    await controller.startMeasurement();
    await controller.nextStep();
    await controller.nextStep();
    await controller.nextStep();
    controller.handleOrientationSample(_sample(174, -36));
    controller.addCurrentPoint();
    await controller.nextStep();

    expect(controller.result?.lowerMeasurements.single.azimuth, 174);
    expect(controller.result?.lowerMeasurements.single.altitude, -36);
    expect(
      controller.result?.points.every((point) => point.minAltitude == 0),
      isTrue,
    );
  });

  test('cancel does not create a partial result', () async {
    await controller.startMeasurement();
    controller.handleOrientationSample(_sample(120, 20));
    controller.addCurrentPoint();
    await controller.cancel();

    expect(controller.status, HorizonMeasurementStatus.cancelled);
    expect(controller.result, isNull);
  });
}
