import 'package:camera/camera.dart';

enum CameraIntrinsicsSource { estimated, cameraMetadata, calibrated }

enum CameraIntrinsicsConfidence { low, medium, high }

class CameraIntrinsics {
  const CameraIntrinsics({
    required this.horizontalFov,
    required this.verticalFov,
    required this.source,
    required this.confidence,
    required this.previewWidth,
    required this.previewHeight,
    required this.sensorOrientation,
    required this.cameraName,
  });

  final double horizontalFov;
  final double verticalFov;
  final CameraIntrinsicsSource source;
  final CameraIntrinsicsConfidence confidence;
  final int previewWidth;
  final int previewHeight;
  final int sensorOrientation;
  final String cameraName;
}

abstract interface class CameraIntrinsicsService {
  Future<CameraIntrinsics> resolve(CameraController controller);
}

class EstimatedCameraIntrinsicsService implements CameraIntrinsicsService {
  const EstimatedCameraIntrinsicsService();

  @override
  Future<CameraIntrinsics> resolve(CameraController controller) async {
    final size = controller.value.previewSize;
    if (size == null) {
      throw StateError('카메라 미리보기 해상도를 확인할 수 없습니다.');
    }
    final lensType = controller.description.lensType;
    final horizontalFov = switch (lensType) {
      CameraLensType.ultraWide => 105.0,
      CameraLensType.telephoto => 35.0,
      _ => 65.0,
    };
    final aspectRatio = size.width / size.height;
    final verticalFov = horizontalFov / aspectRatio;
    return CameraIntrinsics(
      horizontalFov: horizontalFov,
      verticalFov: verticalFov,
      source: CameraIntrinsicsSource.estimated,
      confidence: CameraIntrinsicsConfidence.low,
      previewWidth: size.width.round(),
      previewHeight: size.height.round(),
      sensorOrientation: controller.description.sensorOrientation,
      cameraName: controller.description.name,
    );
  }
}
