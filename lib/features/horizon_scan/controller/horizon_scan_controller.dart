import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/horizon_point.dart';
import '../../../core/services/performance_probe.dart';
import '../models/horizon_scan_sample.dart';
import '../models/horizon_scan_session.dart';
import '../services/camera_intrinsics_service.dart';
import '../services/device_orientation_service.dart';
import '../services/horizon_camera_service.dart';
import '../services/horizon_scan_sampler.dart';
import '../services/horizon_scan_processor.dart';

class HorizonScanController extends ChangeNotifier {
  HorizonScanController({
    required this.observationSiteId,
    required this.observationSiteName,
    required this.latitude,
    required this.longitude,
    required this.orientationService,
    required this.cameraService,
    this.intrinsicsService = const EstimatedCameraIntrinsicsService(),
    this.processor = const HorizonScanProcessor(),
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
  final HorizonScanProcessor processor;

  late HorizonScanSession _session;
  late HorizonScanSampler _sampler;
  StreamSubscription<OrientationSample>? _orientationSubscription;
  OrientationSample? _latestOrientation;
  bool _initializing = false;
  bool _resourcesActive = false;
  bool _closed = false;
  bool _disposed = false;
  Future<void>? _completionFuture;
  int _cameraFrameCallbacks = 0;
  String? _errorMessage;
  bool _permissionPermanentlyDenied = false;
  List<HorizonPoint> _horizonPoints = const [];

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
  List<HorizonPoint> get horizonPoints => List.unmodifiable(_horizonPoints);

  @visibleForTesting
  Future<void> waitForCompletion() => _completionFuture ?? Future.value();

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
      final started = await _startResources();
      if (!started) return;
      _session.status = HorizonScanStatus.scanning;
      _notify();
    } on Object catch (error) {
      await _fail(error);
    } finally {
      _initializing = false;
    }
  }

  Future<bool> _startResources() async {
    await cameraService.initialize();
    _resourcesActive = true;
    if (_closed || _disposed) {
      await _stopResources();
      return false;
    }
    final camera = cameraService.cameraController;
    if (camera == null) throw StateError('카메라를 초기화할 수 없습니다.');
    final intrinsics = await intrinsicsService.resolve(camera);
    if (_closed || _disposed) {
      await _stopResources();
      return false;
    }
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
    if (_closed || _disposed) {
      await _stopResources();
      return false;
    }
    await orientationService.start(latitude: latitude, longitude: longitude);
    if (_closed || _disposed) {
      await _stopResources();
      return false;
    }
    _orientationSubscription = orientationService.samples.listen(
      handleOrientationSample,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail(error));
      },
    );
    return true;
  }

  @visibleForTesting
  void handleOrientationSample(OrientationSample sample) {
    if (!isScanning || _disposed) return;
    _latestOrientation = sample;
    _sampler.updateOrientation(sample);
    _notify();
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed) return;
    _cameraFrameCallbacks++;
    final orientation = _latestOrientation;
    if (!isScanning || orientation == null) return;
    if (!_sampler.needsSample(orientation.azimuth)) return;
    try {
      final frame = HorizonScanSampler.downsampleLuma(image);
      _sampler.recordSample(orientation, frame: frame);
      if (_sampler.isComplete) {
        _requestCompletion();
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
      _requestCompletion();
    } else {
      _notify();
    }
  }

  void _requestCompletion() {
    if (_completionFuture != null || !isScanning || _closed || _disposed) {
      return;
    }
    _session.status = HorizonScanStatus.processing;
    _session.completedAt = DateTime.now();
    _notify();
    _completionFuture = _finishCompletion();
  }

  Future<void> _finishCompletion() async {
    try {
      await _stopResources();
      if (_closed || _disposed) return;
      _horizonPoints = PerformanceProbe.measure(
        'horizon.process',
        () => processor.process(_session),
        state: 'samples=${_session.sampleCount}',
      );
      if (_horizonPoints.isEmpty) {
        _session.addWarning('영상에서 지평선 경계를 찾지 못했습니다.');
      }
      if (_session.coveredBins.length < HorizonScanSampler.totalBins) {
        _session.addWarning('일부 방향의 측정값이 부족합니다.');
      }
      _session.status = HorizonScanStatus.completed;
      _notify();
    } on Object catch (error) {
      if (!_closed && !_disposed) await _fail(error);
    }
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
      final started = await _startResources();
      if (!started) return;
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
    final subscription = _orientationSubscription;
    _orientationSubscription = null;
    if (!_resourcesActive && subscription == null) return;
    _resourcesActive = false;
    await PerformanceProbe.measureAsync(
      'horizon.resources.stop',
      () async {
        await subscription?.cancel();
        await orientationService.stop();
        await cameraService.pause();
      },
      state:
          'status=${_session.status.name} frames=$_cameraFrameCallbacks samples=${_session.sampleCount}',
    );
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
    _resourcesActive = false;
    _completionFuture = null;
    _cameraFrameCallbacks = 0;
    _horizonPoints = const [];
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
