import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/horizon_measurement_result.dart';
import '../models/horizon_scan_sample.dart';
import '../services/device_orientation_service.dart';
import '../services/horizon_camera_service.dart';
import '../services/horizon_measurement_profile_builder.dart';

enum HorizonMeasurementStatus {
  introduction,
  initializing,
  measuring,
  summary,
  paused,
  error,
  cancelled,
}

enum HorizonBoundaryStep { left, right, upper, lower }

class HorizonMeasurementController extends ChangeNotifier {
  HorizonMeasurementController({
    required this.observationSiteId,
    required this.latitude,
    required this.longitude,
    required this.orientationService,
    required this.cameraService,
    this.profileBuilder = const HorizonMeasurementProfileBuilder(),
  });

  final String observationSiteId;
  final double? latitude;
  final double? longitude;
  final DeviceOrientationService orientationService;
  final HorizonCameraService cameraService;
  final HorizonMeasurementProfileBuilder profileBuilder;

  HorizonMeasurementStatus _status = HorizonMeasurementStatus.introduction;
  HorizonBoundaryStep _step = HorizonBoundaryStep.left;
  OrientationSample? _latestOrientation;
  StreamSubscription<OrientationSample>? _orientationSubscription;
  bool _resourcesActive = false;
  bool _disposed = false;
  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;
  final Map<HorizonBoundaryStep, List<HorizonBoundaryMeasurement>>
  _measurements = {
    for (final step in HorizonBoundaryStep.values) step: [],
  };
  HorizonMeasurementResult? _result;

  HorizonMeasurementStatus get status => _status;
  HorizonBoundaryStep get step => _step;
  OrientationSample? get latestOrientation => _latestOrientation;
  CameraController? get cameraController => cameraService.cameraController;
  String? get errorMessage => _errorMessage;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;
  HorizonMeasurementResult? get result => _result;
  bool get canAddPoint =>
      _status == HorizonMeasurementStatus.measuring &&
      _latestOrientation != null;
  bool get canGoBack =>
      _status == HorizonMeasurementStatus.measuring &&
      _step != HorizonBoundaryStep.left;
  List<HorizonBoundaryMeasurement> get currentMeasurements =>
      List.unmodifiable(_measurements[_step]!);

  List<HorizonBoundaryMeasurement> measurementsFor(HorizonBoundaryStep step) =>
      List.unmodifiable(_measurements[step]!);

  Future<void> startMeasurement() async {
    if (_status == HorizonMeasurementStatus.initializing || _disposed) return;
    _resetMeasurements();
    await _startResources();
  }

  Future<void> _startResources() async {
    _status = HorizonMeasurementStatus.initializing;
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    _notify();
    try {
      final permission = await cameraService.requestPermission();
      if (permission != HorizonCameraPermissionState.granted) {
        _permissionPermanentlyDenied =
            permission == HorizonCameraPermissionState.permanentlyDenied;
        throw StateError('카메라 권한이 필요합니다.');
      }
      await cameraService.initialize();
      _resourcesActive = true;
      if (_disposed) {
        await _stopResources();
        return;
      }
      await orientationService.start(latitude: latitude, longitude: longitude);
      _orientationSubscription = orientationService.samples.listen(
        handleOrientationSample,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(_fail(error));
        },
      );
      _status = HorizonMeasurementStatus.measuring;
      _notify();
    } on Object catch (error) {
      await _fail(error);
    }
  }

  @visibleForTesting
  void handleOrientationSample(OrientationSample sample) {
    if (_status != HorizonMeasurementStatus.measuring || _disposed) return;
    _latestOrientation = sample;
    _notify();
  }

  void addCurrentPoint() {
    final orientation = _latestOrientation;
    if (!canAddPoint || orientation == null) return;
    _measurements[_step]!.add(
      HorizonBoundaryMeasurement(
        azimuth: orientation.azimuth,
        altitude: orientation.pitch,
      ),
    );
    _errorMessage = null;
    _notify();
  }

  void deletePoint(int index) {
    final points = _measurements[_step]!;
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
    _notify();
  }

  void deleteLastPoint() {
    final points = _measurements[_step]!;
    if (points.isEmpty) return;
    points.removeLast();
    _notify();
  }

  void clearCurrentPoints() {
    _measurements[_step]!.clear();
    _notify();
  }

  Future<void> nextStep() async {
    if (_status != HorizonMeasurementStatus.measuring) return;
    _errorMessage = null;
    switch (_step) {
      case HorizonBoundaryStep.left:
        _step = HorizonBoundaryStep.right;
      case HorizonBoundaryStep.right:
        final hasLeft = _measurements[HorizonBoundaryStep.left]!.isNotEmpty;
        final hasRight = _measurements[HorizonBoundaryStep.right]!.isNotEmpty;
        if (hasLeft != hasRight) {
          _errorMessage = '왼쪽과 오른쪽 경계는 모두 측정하거나 모두 건너뛰어 주세요.';
          _notify();
          return;
        }
        _step = HorizonBoundaryStep.upper;
      case HorizonBoundaryStep.upper:
        _step = HorizonBoundaryStep.lower;
      case HorizonBoundaryStep.lower:
        try {
          _result = profileBuilder.build(
            observationSiteId: observationSiteId,
            leftMeasurements: _measurements[HorizonBoundaryStep.left]!,
            rightMeasurements: _measurements[HorizonBoundaryStep.right]!,
            upperMeasurements: _measurements[HorizonBoundaryStep.upper]!,
            lowerMeasurements: _measurements[HorizonBoundaryStep.lower]!,
          );
          await _showSummary();
          return;
        } on ArgumentError catch (error) {
          _errorMessage = _argumentMessage(error);
        }
    }
    _notify();
  }

  void previousStep() {
    if (!canGoBack) return;
    _errorMessage = null;
    _step = HorizonBoundaryStep.values[_step.index - 1];
    _notify();
  }

  Future<void> restart() async {
    if (_disposed) return;
    _resetMeasurements();
    await _startResources();
  }

  Future<void> pause() async {
    if (_status != HorizonMeasurementStatus.measuring || _disposed) return;
    _status = HorizonMeasurementStatus.paused;
    await _stopResources();
    _notify();
  }

  Future<void> resume() async {
    if (_status != HorizonMeasurementStatus.paused || _disposed) return;
    await _startResources();
  }

  Future<void> cancel() async {
    if (_disposed) return;
    _status = HorizonMeasurementStatus.cancelled;
    await _stopResources();
    _notify();
  }

  Future<void> close() => _stopResources();

  Future<void> _showSummary() async {
    _status = HorizonMeasurementStatus.summary;
    _notify();
    await _stopResources();
  }

  Future<void> _fail(Object error) async {
    await _stopResources();
    _status = HorizonMeasurementStatus.error;
    final message = error.toString().replaceFirst('Bad state: ', '');
    _errorMessage = message.contains('MissingPluginException')
        ? '이 기기에서는 시야 측정 도우미를 사용할 수 없습니다.'
        : message;
    _notify();
  }

  Future<void> _stopResources() async {
    final subscription = _orientationSubscription;
    _orientationSubscription = null;
    if (!_resourcesActive && subscription == null) return;
    _resourcesActive = false;
    await subscription?.cancel();
    await orientationService.stop();
    await cameraService.pause();
  }

  void _resetMeasurements() {
    _step = HorizonBoundaryStep.left;
    _latestOrientation = null;
    for (final points in _measurements.values) {
      points.clear();
    }
    _result = null;
    _errorMessage = null;
  }

  String _argumentMessage(ArgumentError error) =>
      error.message?.toString() ??
      error.toString().replaceFirst('Invalid argument(s): ', '');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopResources());
    super.dispose();
  }
}
