import 'dart:async';

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

enum HorizonCameraPermissionState { granted, denied, permanentlyDenied }

abstract interface class HorizonCameraService {
  CameraController? get cameraController;

  Future<HorizonCameraPermissionState> requestPermission();

  Future<void> initialize();

  Future<void> startImageStream(void Function(CameraImage image) onImage);

  Future<void> pause();

  Future<void> dispose();
}

class CameraPluginHorizonService implements HorizonCameraService {
  CameraController? _controller;

  @override
  CameraController? get cameraController => _controller;

  @override
  Future<HorizonCameraPermissionState> requestPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return HorizonCameraPermissionState.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return HorizonCameraPermissionState.permanentlyDenied;
    }
    return HorizonCameraPermissionState.denied;
  }

  @override
  Future<void> initialize() async {
    await _disposeController();
    final cameras = await availableCameras();
    final rearCameras = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList(growable: false);
    if (rearCameras.isEmpty) {
      throw StateError('사용 가능한 후면 카메라가 없습니다.');
    }
    final wideCameras = rearCameras
        .where((camera) => camera.lensType == CameraLensType.wide)
        .toList(growable: false);
    final selected = wideCameras.isNotEmpty
        ? wideCameras.first
        : rearCameras.first;
    final controller = CameraController(
      selected,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _controller = controller;
    try {
      await controller.initialize();
    } on Object {
      await _disposeController();
      rethrow;
    }
  }

  @override
  Future<void> startImageStream(
    void Function(CameraImage image) onImage,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 초기화되지 않았습니다.');
    }
    if (!controller.value.isStreamingImages) {
      await controller.startImageStream(onImage);
    }
  }

  @override
  Future<void> pause() => _disposeController();

  @override
  Future<void> dispose() => _disposeController();

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // The platform may already have stopped the stream during lifecycle loss.
      }
    }
    await controller.dispose();
  }
}
