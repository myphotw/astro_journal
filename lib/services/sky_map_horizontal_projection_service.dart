import 'dart:math' as math;
import 'dart:ui';

/// 관측자의 수평 좌표계(Alt/Az)를 하나의 연속적인 천구 화면으로 투영한다.
///
/// 방위각 등거리(azimuthal equidistant) 투영을 모든 FOV에서 동일하게
/// 사용한다. 따라서 전천(180°)과 방향 확대 화면 사이에 투영 전환이나
/// 좌표 점프가 없다. 화면은 실제 하늘을 올려다보는 성도 방향으로
/// 천정에서 북쪽이 위, 동쪽이 왼쪽이다.
abstract final class SkyMapHorizontalProjectionService {
  static const double minViewHeightDeg = 4;
  static const double maxViewHeightDeg = 180;

  static double normalizeAzimuth(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  static double degreesPerPixel({
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    if (canvasSize.height <= 0 || viewHeightDeg <= 0) return 1;
    return viewHeightDeg / canvasSize.height;
  }

  static double angularDegreesToPixels({
    required double degrees,
    required Size canvasSize,
    required double viewHeightDeg,
  }) =>
      degrees /
      degreesPerPixel(canvasSize: canvasSize, viewHeightDeg: viewHeightDeg);

  /// Alt/Az를 화면 좌표로 투영한다.
  ///
  /// [angularDistanceDeg]는 화면 중심에서 대상까지의 실제 구면 각거리다.
  static ({Offset pixel, double angularDistanceDeg}) project({
    required double altitudeDeg,
    required double azimuthDeg,
    required double centerAltitudeDeg,
    required double centerAzimuthDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final target = _Vector3.fromAltAz(altitudeDeg, azimuthDeg);
    final basis = _CameraBasis.forCenter(centerAltitudeDeg, centerAzimuthDeg);
    final dot = basis.forward.dot(target).clamp(-1.0, 1.0);
    final angularDistance = math.acos(dot);
    if (angularDistance < 1e-12) {
      return (
        pixel: Offset(canvasSize.width / 2, canvasSize.height / 2),
        angularDistanceDeg: 0,
      );
    }

    final tangent = (target - basis.forward * dot).normalized;
    final directionX = tangent.dot(basis.right);
    final directionY = tangent.dot(basis.up);
    final radiusPx = angularDegreesToPixels(
      degrees: angularDistance * 180 / math.pi,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    return (
      pixel: Offset(
        canvasSize.width / 2 + directionX * radiusPx,
        canvasSize.height / 2 - directionY * radiusPx,
      ),
      angularDistanceDeg: angularDistance * 180 / math.pi,
    );
  }

  /// 화면 픽셀을 Alt/Az로 역투영한다.
  static ({double altitudeDeg, double azimuthDeg}) unproject({
    required Offset pixel,
    required double centerAltitudeDeg,
    required double centerAzimuthDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final basis = _CameraBasis.forCenter(centerAltitudeDeg, centerAzimuthDeg);
    final delta = pixel - Offset(canvasSize.width / 2, canvasSize.height / 2);
    final radiusPx = delta.distance;
    if (radiusPx < 1e-9) {
      return (
        altitudeDeg: centerAltitudeDeg,
        azimuthDeg: normalizeAzimuth(centerAzimuthDeg),
      );
    }

    final angularDistance =
        radiusPx *
        degreesPerPixel(canvasSize: canvasSize, viewHeightDeg: viewHeightDeg) *
        math.pi /
        180;
    final tangent =
        (basis.right * (delta.dx / radiusPx) +
                basis.up * (-delta.dy / radiusPx))
            .normalized;
    final direction =
        (basis.forward * math.cos(angularDistance) +
                tangent * math.sin(angularDistance))
            .normalized;
    return direction.toAltAz();
  }

  /// 드래그한 만큼 천구가 포인터를 따라오도록 새 화면 중심을 계산한다.
  static ({double altitudeDeg, double azimuthDeg}) panCenter({
    required Offset delta,
    required double centerAltitudeDeg,
    required double centerAzimuthDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final canvasCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
    return unproject(
      pixel: canvasCenter - delta,
      centerAltitudeDeg: centerAltitudeDeg,
      centerAzimuthDeg: centerAzimuthDeg,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
  }

  static Size projectAngularSize({
    required double majorArcmin,
    required double minorArcmin,
    required Size canvasSize,
    required double viewHeightDeg,
  }) => Size(
    angularDegreesToPixels(
      degrees: majorArcmin / 60,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    ),
    angularDegreesToPixels(
      degrees: minorArcmin / 60,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    ),
  );

  /// 대상 중심의 작은 접평면 사각형을 구면 위에 놓은 뒤 화면에 투영한다.
  static List<Offset> projectFovCorners({
    required double objectAltitudeDeg,
    required double objectAzimuthDeg,
    required double centerAltitudeDeg,
    required double centerAzimuthDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final targetBasis = _CameraBasis.forCenter(
      objectAltitudeDeg,
      objectAzimuthDeg,
    );
    final halfWidth = fovWidthDeg / 2;
    final halfHeight = fovHeightDeg / 2;
    final theta = rotationDeg * math.pi / 180;
    final cosTheta = math.cos(theta);
    final sinTheta = math.sin(theta);
    const corners = <(double, double)>[(-1, 1), (1, 1), (1, -1), (-1, -1)];

    return corners
        .map((corner) {
          final localX = corner.$1 * halfWidth;
          final localY = corner.$2 * halfHeight;
          final rotatedX = localX * cosTheta - localY * sinTheta;
          final rotatedY = localX * sinTheta + localY * cosTheta;
          final rhoDeg = math.sqrt(rotatedX * rotatedX + rotatedY * rotatedY);
          _Vector3 point;
          if (rhoDeg < 1e-12) {
            point = targetBasis.forward;
          } else {
            final tangent =
                (targetBasis.right * (rotatedX / rhoDeg) +
                        targetBasis.up * (rotatedY / rhoDeg))
                    .normalized;
            final rho = rhoDeg * math.pi / 180;
            point =
                (targetBasis.forward * math.cos(rho) + tangent * math.sin(rho))
                    .normalized;
          }
          final altAz = point.toAltAz();
          return project(
            altitudeDeg: altAz.altitudeDeg,
            azimuthDeg: altAz.azimuthDeg,
            centerAltitudeDeg: centerAltitudeDeg,
            centerAzimuthDeg: centerAzimuthDeg,
            canvasSize: canvasSize,
            viewHeightDeg: viewHeightDeg,
          ).pixel;
        })
        .toList(growable: false);
  }

  static double angularSeparationDeg({
    required double altitudeADeg,
    required double azimuthADeg,
    required double altitudeBDeg,
    required double azimuthBDeg,
  }) {
    final a = _Vector3.fromAltAz(altitudeADeg, azimuthADeg);
    final b = _Vector3.fromAltAz(altitudeBDeg, azimuthBDeg);
    return math.acos(a.dot(b).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// 구면상으로 가까운 별자리 선분만 유지해 화면을 가로지르는 chord를 막는다.
  static bool shouldDrawConstellationSegment({
    required double altitudeADeg,
    required double azimuthADeg,
    required double altitudeBDeg,
    required double azimuthBDeg,
    required Offset projectedA,
    required Offset projectedB,
    required Size canvasSize,
    required double viewHeightDeg,
  }) {
    final separation = angularSeparationDeg(
      altitudeADeg: altitudeADeg,
      azimuthADeg: azimuthADeg,
      altitudeBDeg: altitudeBDeg,
      azimuthBDeg: azimuthBDeg,
    );
    if (separation < 1e-3 || separation > 45) return false;
    final expected = angularDegreesToPixels(
      degrees: separation,
      canvasSize: canvasSize,
      viewHeightDeg: viewHeightDeg,
    );
    final actual = (projectedA - projectedB).distance;
    return actual <= expected * 1.35 + 2;
  }
}

class _CameraBasis {
  const _CameraBasis({
    required this.forward,
    required this.right,
    required this.up,
  });

  factory _CameraBasis.forCenter(double altitudeDeg, double azimuthDeg) {
    final forward = _Vector3.fromAltAz(altitudeDeg, azimuthDeg);
    const zenith = _Vector3(0, 0, 1);
    var right = forward.cross(zenith);
    if (right.length < 1e-9) {
      // 천정의 roll 특이점에서는 N-up / E-left인 성도 방향을 고정한다.
      return _CameraBasis(
        forward: forward,
        right: const _Vector3(-1, 0, 0),
        up: const _Vector3(0, 1, 0),
      );
    } else {
      right = right.normalized;
    }
    final up = right.cross(forward).normalized;
    return _CameraBasis(forward: forward, right: right, up: up);
  }

  final _Vector3 forward;
  final _Vector3 right;
  final _Vector3 up;
}

class _Vector3 {
  const _Vector3(this.x, this.y, this.z);

  factory _Vector3.fromAltAz(double altitudeDeg, double azimuthDeg) {
    final altitude = altitudeDeg * math.pi / 180;
    final azimuth = azimuthDeg * math.pi / 180;
    final cosAltitude = math.cos(altitude);
    return _Vector3(
      cosAltitude * math.sin(azimuth), // east
      cosAltitude * math.cos(azimuth), // north
      math.sin(altitude), // zenith
    );
  }

  final double x;
  final double y;
  final double z;

  double get length => math.sqrt(x * x + y * y + z * z);
  _Vector3 get normalized {
    final magnitude = length;
    return magnitude < 1e-12 ? this : this * (1 / magnitude);
  }

  double dot(_Vector3 other) => x * other.x + y * other.y + z * other.z;
  _Vector3 cross(_Vector3 other) => _Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );
  _Vector3 operator +(_Vector3 other) =>
      _Vector3(x + other.x, y + other.y, z + other.z);
  _Vector3 operator -(_Vector3 other) =>
      _Vector3(x - other.x, y - other.y, z - other.z);
  _Vector3 operator *(double scale) =>
      _Vector3(x * scale, y * scale, z * scale);

  ({double altitudeDeg, double azimuthDeg}) toAltAz() {
    final altitude = math.asin(z.clamp(-1.0, 1.0)) * 180 / math.pi;
    final azimuth = math.atan2(x, y) * 180 / math.pi;
    return (
      altitudeDeg: altitude,
      azimuthDeg: SkyMapHorizontalProjectionService.normalizeAzimuth(azimuth),
    );
  }
}
