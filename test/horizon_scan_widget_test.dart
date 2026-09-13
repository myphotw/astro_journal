import 'dart:async';

import 'package:astro_journal/features/horizon_scan/controller/horizon_measurement_controller.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_measurement_result.dart';
import 'package:astro_journal/features/horizon_scan/models/horizon_scan_sample.dart';
import 'package:astro_journal/features/horizon_scan/services/device_orientation_service.dart';
import 'package:astro_journal/features/horizon_scan/services/horizon_camera_service.dart';
import 'package:astro_journal/features/horizon_scan/services/screen_awake_service.dart';
import 'package:astro_journal/features/horizon_scan/view/horizon_scan_screen.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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
  _FakeCameraService({this.permission = HorizonCameraPermissionState.granted});

  final HorizonCameraPermissionState permission;
  final controller = CameraController(
    const CameraDescription(
      name: 'fake',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    ResolutionPreset.medium,
  );

  @override
  CameraController get cameraController => controller;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<HorizonCameraPermissionState> requestPermission() async => permission;

  @override
  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {}

  @override
  Future<void> dispose() async {}
}

class _FakeScreenAwakeService implements ScreenAwakeService {
  int enableCalls = 0;
  int disableCalls = 0;
  bool enabled = false;

  @override
  Future<void> enable() async {
    enableCalls++;
    enabled = true;
  }

  @override
  Future<void> disable() async {
    disableCalls++;
    enabled = false;
  }
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

HorizonMeasurementController _controller(
  _FakeOrientationService orientation,
  _FakeCameraService camera,
) => HorizonMeasurementController(
  observationSiteId: 'site',
  latitude: 37.5,
  longitude: 127,
  orientationService: orientation,
  cameraService: camera,
);

Widget _app(
  HorizonMeasurementController controller, {
  ScreenAwakeService? screenAwakeService,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: HorizonScanScreen(
    observationSiteId: 'site',
    observationSiteName: '테스트 관측지',
    controller: controller,
    manageSystemOrientation: false,
    screenAwakeService: screenAwakeService ?? _FakeScreenAwakeService(),
  ),
);

void main() {
  testWidgets('keeps screen awake only while the helper is foreground', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    final screenAwake = _FakeScreenAwakeService();

    await tester.pumpWidget(
      _app(controller, screenAwakeService: screenAwake),
    );
    await tester.pump();
    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.enabled, isTrue);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();
    expect(screenAwake.disableCalls, 1);
    expect(screenAwake.enabled, isFalse);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(screenAwake.enableCalls, 2);
    expect(screenAwake.enabled, isTrue);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();
    expect(screenAwake.disableCalls, 2);
    expect(screenAwake.enabled, isFalse);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();
    expect(screenAwake.enableCalls, 3);
    expect(screenAwake.enabled, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(screenAwake.disableCalls, 3);
    expect(screenAwake.enabled, isFalse);

    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('close disables screen awake before leaving the helper', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    final screenAwake = _FakeScreenAwakeService();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            key: const Key('open-horizon-helper'),
            onPressed: () {
              unawaited(
                Navigator.of(context).push<HorizonMeasurementResult>(
                  MaterialPageRoute(
                    builder: (_) => HorizonScanScreen(
                      observationSiteId: 'site',
                      observationSiteName: '테스트 관측지',
                      controller: controller,
                      manageSystemOrientation: false,
                      screenAwakeService: screenAwake,
                    ),
                  ),
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-horizon-helper')));
    await tester.pumpAndSettle();
    expect(screenAwake.enabled, isTrue);

    await tester.tap(find.byKey(const Key('close-horizon-scan')));
    await tester.pumpAndSettle();
    expect(screenAwake.enabled, isFalse);
    expect(screenAwake.disableCalls, 1);

    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('shows telescope-position guidance before measurement', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    final screenAwake = _FakeScreenAwakeService();
    await tester.pumpWidget(
      _app(controller, screenAwakeService: screenAwake),
    );

    expect(
      find.byKey(const Key('horizon-measurement-introduction')),
      findsOneWidget,
    );
    expect(find.textContaining('실제 망원경이 설치되는 위치'), findsOneWidget);
    expect(find.textContaining('렌즈 높이와 위치'), findsOneWidget);
    expect(find.byKey(const Key('start-horizon-measurement')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('collects boundary points with live aim and reaches summary', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    final screenAwake = _FakeScreenAwakeService();
    await tester.pumpWidget(
      _app(controller, screenAwakeService: screenAwake),
    );
    await tester.tap(find.byKey(const Key('start-horizon-measurement')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('horizon-measurement-crosshair')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-step')))
          .data,
      '왼쪽 경계 · 측정 지점 0개 · 1/4',
    );
    controller.handleOrientationSample(_sample(120, 20));
    await tester.pump();
    expect(find.text('Az 120°'), findsOneWidget);
    expect(find.text('Alt 20°'), findsOneWidget);
    expect(find.text('남동'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-point-count')))
          .data,
      '측정 지점 1개',
    );
    expect(
      find.byKey(const Key('delete-horizon-boundary-point-0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('next-horizon-boundary-step')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-step')))
          .data,
      '오른쪽 경계 · 측정 지점 0개 · 2/4',
    );
    controller.handleOrientationSample(_sample(215, 20));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('next-horizon-boundary-step')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-step')))
          .data,
      '상단 경계 · 측정 지점 0개 · 3/4',
    );
    controller.handleOrientationSample(_sample(170, 65));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('next-horizon-boundary-step')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-step')))
          .data,
      '하단 경계 · 측정 지점 0개 · 4/4',
    );
    controller.handleOrientationSample(_sample(180, 50));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();
    expect(controller.status, HorizonMeasurementStatus.measuring);
    expect(controller.step, HorizonBoundaryStep.lower);
    await tester.tap(find.byKey(const Key('next-horizon-boundary-step')));
    expect(controller.status, HorizonMeasurementStatus.summary);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('horizon-measurement-summary')),
      findsOneWidget,
    );
    expect(screenAwake.enabled, isTrue);
    expect(find.text('120° ~ 215°'), findsOneWidget);
    expect(find.text('나머지 방위'), findsOneWidget);
    expect(find.byKey(const Key('restart-horizon-measurement')), findsOneWidget);
    expect(find.byKey(const Key('save-horizon-measurement')), findsOneWidget);
    final rawValuesToggle = find.byKey(
      const Key('horizon-measurement-raw-values-toggle'),
    );
    expect(rawValuesToggle, findsOneWidget);
    expect(
      find.byKey(const Key('horizon-measurement-raw-values')),
      findsNothing,
    );
    await tester.ensureVisible(rawValuesToggle);
    await tester.tap(rawValuesToggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('horizon-measurement-raw-values')),
      findsOneWidget,
    );
    expect(find.text('남동 · Az 120° / Alt 20°'), findsOneWidget);
    expect(find.text('남서 · Az 215° / Alt 20°'), findsOneWidget);
    expect(find.text('남 · Az 170° / Alt 65°'), findsOneWidget);
    expect(find.text('남 · Az 180° / Alt 50°'), findsOneWidget);
    expect(find.text('적용 방위 120°'), findsOneWidget);
    expect(find.text('적용 방위 215°'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('supports last deletion, reset, previous, and empty next', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('start-horizon-measurement')));
    await tester.pumpAndSettle();

    controller.handleOrientationSample(_sample(120, 20));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('delete-last-horizon-boundary-point')),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-point-count')))
          .data,
      '측정 지점 0개',
    );

    controller.handleOrientationSample(_sample(125, 22));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-horizon-boundary-point')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reset-current-horizon-boundary')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('horizon-boundary-point-count')))
          .data,
      '측정 지점 0개',
    );

    await tester.tap(find.byKey(const Key('next-horizon-boundary-step')));
    await tester.pump();
    expect(
      find.byKey(const Key('previous-horizon-boundary-step')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('many points stay in a bounded scroll panel on a small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orientation = _FakeOrientationService();
    final controller = _controller(orientation, _FakeCameraService());
    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('start-horizon-measurement')));
    await tester.pumpAndSettle();

    for (var index = 0; index < 10; index++) {
      controller.handleOrientationSample(
        _sample(100 + index * 5, 10 + index.toDouble()),
      );
      controller.addCurrentPoint();
    }
    await tester.pump();

    final crosshair = find.byKey(const Key('horizon-measurement-crosshair'));
    final hud = find.byKey(const Key('horizon-measurement-top-hud'));
    final panel = find.byKey(const Key('horizon-measurement-bottom-panel'));
    final pointList = find.byKey(const Key('horizon-boundary-points-scroll'));
    expect(crosshair, findsOneWidget);
    expect(hud, findsOneWidget);
    expect(panel, findsOneWidget);
    expect(pointList, findsOneWidget);
    expect(tester.widget(pointList), isA<ListView>());
    expect(tester.getSize(panel).height, lessThanOrEqualTo(182));
    expect(tester.getRect(hud).bottom, lessThan(tester.getRect(crosshair).top));
    expect(
      tester.getRect(panel).top,
      greaterThan(tester.getRect(crosshair).bottom),
    );
    expect(find.byKey(const Key('add-horizon-boundary-point')), findsOneWidget);
    expect(
      find.byKey(const Key('delete-last-horizon-boundary-point')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reset-current-horizon-boundary')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('next-horizon-boundary-step')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.streamController.close();
  });

  testWidgets('permission error appears after measurement starts', (
    tester,
  ) async {
    final orientation = _FakeOrientationService();
    final controller = _controller(
      orientation,
      _FakeCameraService(permission: HorizonCameraPermissionState.denied),
    );
    await tester.pumpWidget(_app(controller));
    await tester.tap(find.byKey(const Key('start-horizon-measurement')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('horizon-measurement-error')), findsOneWidget);
    expect(find.textContaining('카메라 권한'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await orientation.streamController.close();
  });
}
