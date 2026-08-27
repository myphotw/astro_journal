import 'dart:async';

import 'package:astro_journal/features/horizon_scan/controller/horizon_scan_controller.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_session.dart';
import 'package:astro_journal/features/horizon_scan/services/camera_intrinsics_service.dart';
import 'package:astro_journal/features/horizon_scan/services/device_orientation_service.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_camera_service.dart';
import 'package:astro_journal/features/horizon_scan/view/horizon_scan_screen.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrientationService implements DeviceOrientationService {
  final controller = StreamController<OrientationSample>.broadcast();

  @override
  Stream<OrientationSample> get samples => controller.stream;

  @override
  Future<void> start({double? latitude, double? longitude}) async {}

  @override
  Future<void> stop() => SynchronousFuture<void>(null);
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
  int pauses = 0;

  @override
  CameraController get cameraController => _controller;

  @override
  Future<HorizonCameraPermissionState> requestPermission() async => permission;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {}

  @override
  Future<void> pause() {
    pauses++;
    return SynchronousFuture<void>(null);
  }

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

HorizonScanController _scanController(
  _FakeOrientationService orientation,
  _FakeCameraService camera,
) => HorizonScanController(
  observationSiteId: 'site',
  observationSiteName: '테스트 관측지',
  latitude: 37.5,
  longitude: 127,
  orientationService: orientation,
  cameraService: camera,
  intrinsicsService: _FakeIntrinsicsService(),
);

Widget _app(HorizonScanController controller) => MaterialApp(
  theme: ThemeData.dark(),
  home: HorizonScanScreen(
    observationSiteId: 'site',
    observationSiteName: '테스트 관측지',
    controller: controller,
    manageSystemOrientation: false,
  ),
);

OrientationSample _sample(double azimuth, int timestampNanos) =>
    OrientationSample(
      sampledAt: DateTime(2026),
      sensorTimestampNanos: timestampNanos,
      azimuth: azimuth,
      pitch: 0,
      roll: 0,
      accuracy: HorizonSensorAccuracy.good,
      trueNorthApplied: true,
    );

void main() {
  testWidgets('shows a recoverable permission error', (tester) async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService(
      permission: HorizonCameraPermissionState.denied,
    );
    final controller = _scanController(orientation, camera);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('horizon-scan-error')), findsOneWidget);
    expect(find.textContaining('카메라 권한'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.controller.close();
  });

  testWidgets('shows progress and a too-fast guide', (tester) async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService();
    final controller = _scanController(orientation, camera);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('horizon-scan-ready')), findsOneWidget);

    controller.recordSampleForTest(_sample(0, 0));
    controller.recordSampleForTest(_sample(5, 100000000));
    await tester.pump();
    expect(find.text('샘플'), findsOneWidget);
    expect(find.text('2/72'), findsOneWidget);
    expect(find.text('조금 천천히 움직여 주세요.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.controller.close();
  });

  testWidgets('shows completion summary after a full scan', (tester) async {
    final orientation = _FakeOrientationService();
    final camera = _FakeCameraService();
    final controller = _scanController(orientation, camera);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    for (var index = 0; index < 72; index++) {
      controller.recordSampleForTest(_sample(index * 5, index * 500000000));
    }
    expect(controller.session.status, HorizonScanStatus.processing);
    await tester.runAsync(controller.waitForCompletion);
    await tester.pump();
    expect(controller.session.status, HorizonScanStatus.completed);

    expect(controller.session.status, HorizonScanStatus.completed);
    expect(find.byKey(const Key('horizon-scan-summary')), findsOneWidget);
    expect(find.byKey(const Key('horizon-visibility-legend')), findsOneWidget);
    expect(find.text('장애물 / 촬영 불가 영역'), findsOneWidget);
    expect(find.text('미측정 / 불확실'), findsOneWidget);
    expect(find.text('시야 스캔 완료'), findsOneWidget);
    expect(find.byKey(const Key('restart-horizon-scan')), findsOneWidget);
    expect(find.byKey(const Key('finish-horizon-scan')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.controller.close();
  });
}
