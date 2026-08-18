import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/horizon_scan_sample.dart';
import '../models/horizon_scan_session.dart';
import '../services/camera_intrinsics_service.dart';
import '../services/device_orientation_service.dart';
import '../services/horizon_camera_service.dart';
import '../services/horizon_scan_sampler.dart';

class HorizonScanController extends ChangeNotifier {
  HorizonScanController({
    required this.observationSiteId,
    required this.observationSiteName,
    required this.latitude,
    required this.longitude,
    required this.orientationService,
    required this.cameraService,
    this.intrinsicsService = const EstimatedCameraIntrinsicsService(),
  }) {
    _createSession();
  }

  final String observationSiteId;
  final String observationSiteName;
  final double? latitude;
  final double? longitude;
  final DeviceOrientationService orientationService;
  final HorizonCameraService cameraService;
  final CameraIntrinsicsService intrinsicsService;

  late HorizonScanSession _session;
  late HorizonScanSampler _sampler;
  StreamSubscription<OrientationSample>? _orientationSubscription;
  OrientationSample? _latestOrientation;
  bool _initializing = false;
  bool _closed = false;
  bool _disposed = false;
  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;

  HorizonScanSession get session => _session;
  CameraController? get cameraController => cameraService.cameraController;
  OrientationSample? get latestOrientation => _latestOrientation;
  String? get errorMessage => _errorMessage;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;
  bool get isScanning => _session.status == HorizonScanStatus.scanning;
  bool get isComplete => _session.status == HorizonScanStatus.completed;
  double get coverage =>
      _session.coverageFraction(HorizonScanSampler.totalBins);
  List<int> get missingBins =>
      _session.missingBins(HorizonScanSampler.totalBins);

  Future<void> initialize() async {
    if (_initializing || isScanning || _disposed) return;
    _initializing = true;
    _errorMessage = null;
    _permissionPermanentlyDenied = false;
    _session.status = HorizonScanStatus.initializing;
    _notify();
    try {
      final permission = await cameraService.requestPermission();
      if (permission != HorizonCameraPermissionState.granted) {
        _permissionPermanentlyDenied =
            permission == HorizonCameraPermissionState.permanentlyDenied;
        throw StateError('카메라 권한이 필요합니다.');
      }
      await _startResources();
      _session.status = HorizonScanStatus.scanning;
      _notify();
    } on Object catch (error) {
      await _fail(error);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _startResources() async {
    await cameraService.initialize();
    final camera = cameraService.cameraController;
    if (camera == null) throw StateError('카메라를 초기화할 수 없습니다.');
    final intrinsics = await intrinsicsService.resolve(camera);
    _session.cameraInformation = HorizonScanCameraInformation(
      cameraName: intrinsics.cameraName,
      previewWidth: intrinsics.previewWidth,
      previewHeight: intrinsics.previewHeight,
      sensorOrientation: intrinsics.sensorOrientation,
      horizontalFov: intrinsics.horizontalFov,
      verticalFov: intrinsics.verticalFov,
      intrinsicsSource: intrinsics.source.name,
      intrinsicsConfidence: intrinsics.confidence.name,
    );
    await cameraService.startImageStream(_onCameraImage);
    await orientationService.start(latitude: latitude, longitude: longitude);
    _orientationSubscription = orientationService.samples.listen(
      handleOrientationSample,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail(error));
      },
    );
  }

  @visibleForTesting
  void handleOrientationSample(OrientationSample sample) {
    if (!isScanning || _disposed) return;
    _latestOrientation = sample;
    _sampler.updateOrientation(sample);
    _notify();
  }

  void _onCameraImage(CameraImage image) {
    final orientation = _latestOrientation;
    if (!isScanning || orientation == null || _disposed) return;
    if (!_sampler.needsSample(orientation.azimuth)) return;
    try {
      final frame = HorizonScanSampler.downsampleLuma(image);
      _sampler.recordSample(orientation, frame: frame);
      if (_sampler.isComplete) {
        unawaited(_complete());
      } else {
        _notify();
      }
    } on Object catch (error) {
      _session.addWarning('일부 카메라 프레임을 처리하지 못했습니다: $error');
      _notify();
    }
  }

  @visibleForTesting
  void recordSampleForTest(
    OrientationSample sample, {
    HorizonFrameReference? frame,
  }) {
    if (!isScanning || _disposed) return;
    _latestOrientation = sample;
    _sampler.updateOrientation(sample);
    _sampler.recordSample(sample, frame: frame);
    if (_sampler.isComplete) {
      unawaited(_complete());
    } else {
      _notify();
    }
  }

  Future<void> _complete() async {
    if (_session.status == HorizonScanStatus.completed) {
      await _stopResources();
      _notify();
      return;
    }
    _session.status = HorizonScanStatus.completed;
    _session.completedAt = DateTime.now();
    await _stopResources();
    _notify();
  }

  Future<void> pause() async {
    if (!isScanning || _disposed) return;
    _session.status = HorizonScanStatus.paused;
    await _stopResources();
    _notify();
  }

  Future<void> resume() async {
    if (_session.status != HorizonScanStatus.paused || _disposed) return;
    try {
      await _startResources();
      _session.status = HorizonScanStatus.scanning;
      _notify();
    } on Object catch (error) {
      await _fail(error);
    }
  }

  Future<void> restart() async {
    if (_disposed) return;
    await _stopResources();
    _session.clearFrames();
    _createSession();
    await initialize();
  }

  Future<void> cancel() async {
    if (_disposed) return;
    _session.status = HorizonScanStatus.cancelled;
    await _stopResources();
    _session.clearFrames();
    _notify();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stopResources();
    _session.clearFrames();
  }

  Future<void> _stopResources() async {
    await _orientationSubscription?.cancel();
    _orientationSubscription = null;
    await orientationService.stop();
    await cameraService.pause();
  }

  Future<void> _fail(Object error) async {
    await _stopResources();
    _session.status = HorizonScanStatus.error;
    final message = error.toString().replaceFirst('Bad state: ', '');
    _errorMessage = message.contains('MissingPluginException')
        ? '이 기기에서는 자동 시야 측정을 사용할 수 없습니다.'
        : message;
    _notify();
  }

  void _createSession() {
    _session = HorizonScanSession(
      id: const Uuid().v4(),
      observationSiteId: observationSiteId,
      startedAt: DateTime.now(),
      status: HorizonScanStatus.idle,
    );
    _sampler = HorizonScanSampler(_session);
    _latestOrientation = null;
    _errorMessage = null;
    _closed = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
