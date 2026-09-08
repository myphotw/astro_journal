import 'dart:math' as math;

import 'plate_solve/fits_wcs_parser.dart';

/// 접평면 IWC 오프셋 (degrees). +x=+RA(동), +y=+Dec(북).
class TangentPlaneOffset {
  const TangentPlaneOffset(this.xDeg, this.yDeg);

  final double xDeg;
  final double yDeg;
}

/// 표시용 픽셀 좌표 (0,0 = 좌상단, +Y = 아래).
class PixelOffset {
  const PixelOffset(this.x, this.y);

  final double x;
  final double y;
}

/// Plate Solve WCS 기반 RA/Dec → 픽셀 변환.
///
/// 우선순위:
/// 1. FITS WCS (CRVAL/CRPIX/CD) — Astrometry.net `wcs_file`
/// 2. orientation + parity + pixscale 로 CD 재구성 (폴백)
class PlateSolveProjection {
  PlateSolveProjection._();

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;

  /// RA/Dec → TAN IWC (degrees). Astrometry.net `star_coords`와 동일.
  static TangentPlaneOffset tangentIwcDeg({
    required double centerRaDeg,
    required double centerDecDeg,
    required double targetRaDeg,
    required double targetDecDeg,
  }) {
    final ra0 = _toRad(centerRaDeg);
    final dec0 = _toRad(centerDecDeg);
    final ra = _toRad(targetRaDeg);
    final dec = _toRad(targetDecDeg);

    final deltaRa = ra - ra0;
    final cosC = math.sin(dec0) * math.sin(dec) +
        math.cos(dec0) * math.cos(dec) * math.cos(deltaRa);

    if (cosC <= 1e-12) {
      return const TangentPlaneOffset(double.nan, double.nan);
    }

    final xRad = (math.cos(dec) * math.sin(deltaRa)) / cosC;
    final yRad = (math.cos(dec0) * math.sin(dec) -
            math.sin(dec0) * math.cos(dec) * math.cos(deltaRa)) /
        cosC;

    return TangentPlaneOffset(_toDeg(xRad), _toDeg(yRad));
  }

  /// Astrometry WCS → 입력 이미지 표시 픽셀 (0-based).
  ///
  /// WCS의 1-based pixel center에서 0.5만 뺀다. Astrometry가 푼
  /// JPEG/PNG의 X/Y pixel axis는 그대로 유지하며, CD 행렬에 포함된
  /// 회전/parity도 다시 적용하지 않는다.
  static PixelOffset worldToPixelFromWcs({
    required FitsWcsHeader wcs,
    required double targetRaDeg,
    required double targetDecDeg,
    double? rasterWidth,
    double? rasterHeight,
    bool rasterizeFitsAxes = false,
  }) {
    return _tryWorldToPixelFromWcs(
          wcs: wcs,
          targetRaDeg: targetRaDeg,
          targetDecDeg: targetDecDeg,
          rasterHeight: rasterHeight,
          rasterizeFitsAxes: rasterizeFitsAxes,
        ) ??
        _wcsReferencePixel(
          wcs,
          rasterHeight: rasterHeight,
          rasterizeFitsAxes: rasterizeFitsAxes,
        );
  }

  static PixelOffset? _tryWorldToPixelFromWcs({
    required FitsWcsHeader wcs,
    required double targetRaDeg,
    required double targetDecDeg,
    double? rasterHeight,
    required bool rasterizeFitsAxes,
  }) {
    if (!wcs.isValid) return null;
    final iwc = tangentIwcDeg(
      centerRaDeg: wcs.crval1,
      centerDecDeg: wcs.crval2,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
    );
    if (!iwc.xDeg.isFinite || !iwc.yDeg.isFinite) return null;

    final det = wcs.cd11 * wcs.cd22 - wcs.cd12 * wcs.cd21;
    if (!det.isFinite || det.abs() < 1e-30) return null;

    final inv11 = wcs.cd22 / det;
    final inv12 = -wcs.cd12 / det;
    final inv21 = -wcs.cd21 / det;
    final inv22 = wcs.cd11 / det;

    final distortedU = inv11 * iwc.xDeg + inv12 * iwc.yDeg;
    final distortedV = inv21 * iwc.xDeg + inv22 * iwc.yDeg;
    if (!distortedU.isFinite || !distortedV.isFinite) return null;

    final undistorted = _inverseSip(wcs.sip, distortedU, distortedV);
    if (undistorted == null) return null;

    final fitsX = wcs.crpix1 + undistorted.$1;
    final fitsY = wcs.crpix2 + undistorted.$2;
    final fitsDisplayX = fitsX - 0.5;
    final fitsDisplayY = fitsY - 0.5;
    final displayHeight = rasterHeight ?? wcs.rasterHeight;
    final displayX = fitsDisplayX;
    final displayY = rasterizeFitsAxes && displayHeight != null
        ? displayHeight - fitsDisplayY
        : fitsDisplayY;
    if (!displayX.isFinite || !displayY.isFinite) return null;
    return PixelOffset(displayX, displayY);
  }

  static (double, double)? _inverseSip(
    FitsSipDistortion? sip,
    double distortedU,
    double distortedV,
  ) {
    if (sip == null) return (distortedU, distortedV);
    if (!sip.isValid) return null;

    if (sip.hasInverse) {
      final u = distortedU + sip.evaluateAp(distortedU, distortedV);
      final v = distortedV + sip.evaluateBp(distortedU, distortedV);
      return u.isFinite && v.isFinite ? (u, v) : null;
    }

    if (!sip.hasForward) return null;
    var u = distortedU;
    var v = distortedV;
    const maxIterations = 20;
    const convergencePixels = 1e-7;
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      final nextU = distortedU - sip.evaluateA(u, v);
      final nextV = distortedV - sip.evaluateB(u, v);
      if (!nextU.isFinite || !nextV.isFinite) return null;
      final delta = math.max((nextU - u).abs(), (nextV - v).abs());
      u = nextU;
      v = nextV;
      if (delta <= convergencePixels) return (u, v);
    }
    return null;
  }

  static PixelOffset _wcsReferencePixel(
    FitsWcsHeader wcs, {
    double? rasterHeight,
    required bool rasterizeFitsAxes,
  }) {
    final x = wcs.crpix1 - 0.5;
    final fitsY = wcs.crpix2 - 0.5;
    final height = rasterHeight ?? wcs.rasterHeight;
    final y = rasterizeFitsAxes && height != null ? height - fitsY : fitsY;
    return PixelOffset(x, y);
  }

  /// orientation/parity/pixscale 로 CD를 재구성 (wcs 파일 없을 때).
  static ({double cd11, double cd12, double cd21, double cd22}) cdMatrix({
    required double pixelScaleArcsec,
    required double orientationDeg,
    double parity = 1.0,
  }) {
    final s = pixelScaleArcsec / 3600.0;
    final o = _toRad(orientationDeg);
    final cosO = math.cos(o);
    final sinO = math.sin(o);
    final p = parity >= 0 ? 1.0 : -1.0;

    if (p > 0) {
      return (
        cd11: s * cosO,
        cd12: s * sinO,
        cd21: -s * sinO,
        cd22: s * cosO,
      );
    }
    return (
      cd11: -s * cosO,
      cd12: s * sinO,
      cd21: s * sinO,
      cd22: s * cosO,
    );
  }

  /// Astrometry.net calibration API scalar values reconstructed for a raster
  /// image (JPEG/PNG) whose origin is at the top-left.
  ///
  /// Astrometry.net flips `orientation` for JPEG/PNG display coordinates, but
  /// returns the parity of the unflipped FITS CD matrix. Reusing [cdMatrix]
  /// with those mixed conventions mirrors the east/west component. This
  /// matrix keeps the API orientation and converts that raw parity into the
  /// displayed raster coordinate system.
  static ({double cd11, double cd12, double cd21, double cd22})
  rasterCalibrationCdMatrix({
    required double pixelScaleArcsec,
    required double orientationDeg,
    double parity = 1.0,
  }) {
    final s = pixelScaleArcsec / 3600.0;
    final o = _toRad(orientationDeg);
    final cosO = math.cos(o);
    final sinO = math.sin(o);
    final p = parity >= 0 ? 1.0 : -1.0;

    return (
      cd11: -p * s * cosO,
      cd12: -p * s * sinO,
      cd21: -s * sinO,
      cd22: s * cosO,
    );
  }

  /// 폴백: calibration 스칼라로 변환 (CRPIX=이미지 중심 가정).
  static PixelOffset worldToPixel({
    required double centerRaDeg,
    required double centerDecDeg,
    required double targetRaDeg,
    required double targetDecDeg,
    required double orientationDeg,
    required double pixelScaleArcsec,
    required int imageWidth,
    required int imageHeight,
    double parity = 1.0,
    FitsWcsHeader? wcs,
  }) {
    if (wcs != null && wcs.isValid) {
      final fullWcsPixel = _tryWorldToPixelFromWcs(
        wcs: wcs,
        targetRaDeg: targetRaDeg,
        targetDecDeg: targetDecDeg,
        rasterHeight: imageHeight.toDouble(),
        rasterizeFitsAxes: false,
      );
      if (fullWcsPixel != null) return fullWcsPixel;
    }

    if (pixelScaleArcsec <= 0 || imageWidth <= 0 || imageHeight <= 0) {
      return PixelOffset(imageWidth / 2.0, imageHeight / 2.0);
    }

    // crpix_center 가정: CRPIX=(W+1)/2,(H+1)/2 (FITS), CRVAL=field center
    final cd = rasterCalibrationCdMatrix(
      pixelScaleArcsec: pixelScaleArcsec,
      orientationDeg: orientationDeg,
      parity: parity,
    );
    final header = FitsWcsHeader(
      crval1: centerRaDeg,
      crval2: centerDecDeg,
      crpix1: (imageWidth + 1) / 2.0,
      crpix2: (imageHeight + 1) / 2.0,
      cd11: cd.cd11,
      cd12: cd.cd12,
      cd21: cd.cd21,
      cd22: cd.cd22,
      imageW: imageWidth.toDouble(),
      imageH: imageHeight.toDouble(),
    );

    return worldToPixelFromWcs(
      wcs: header,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
      rasterizeFitsAxes: false,
    );
  }

  /// Projects an astronomical position angle (north through east) into the
  /// raster image and returns the clockwise Canvas angle in radians.
  static double positionAngleToPixelRadians({
    required double centerRaDeg,
    required double centerDecDeg,
    required double targetRaDeg,
    required double targetDecDeg,
    required double positionAngleDeg,
    required double orientationDeg,
    required double pixelScaleArcsec,
    required int imageWidth,
    required int imageHeight,
    double parity = 1.0,
    FitsWcsHeader? wcs,
  }) {
    final center = worldToPixel(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
      orientationDeg: orientationDeg,
      pixelScaleArcsec: pixelScaleArcsec,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      parity: parity,
      wcs: wcs,
    );
    final endpoint = _destinationPoint(
      raDeg: targetRaDeg,
      decDeg: targetDecDeg,
      bearingDeg: positionAngleDeg,
      distanceDeg: 1 / 60,
    );
    final projected = worldToPixel(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      targetRaDeg: endpoint.raDeg,
      targetDecDeg: endpoint.decDeg,
      orientationDeg: orientationDeg,
      pixelScaleArcsec: pixelScaleArcsec,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      parity: parity,
      wcs: wcs,
    );
    return math.atan2(projected.y - center.y, projected.x - center.x);
  }

  static ({double raDeg, double decDeg}) _destinationPoint({
    required double raDeg,
    required double decDeg,
    required double bearingDeg,
    required double distanceDeg,
  }) {
    final ra = _toRad(raDeg);
    final dec = _toRad(decDeg);
    final bearing = _toRad(bearingDeg);
    final distance = _toRad(distanceDeg);
    final sinDec =
        math.sin(dec) * math.cos(distance) +
        math.cos(dec) * math.sin(distance) * math.cos(bearing);
    final destinationDec = math.asin(sinDec.clamp(-1.0, 1.0));
    final destinationRa =
        ra +
        math.atan2(
          math.sin(bearing) * math.sin(distance) * math.cos(dec),
          math.cos(distance) - math.sin(dec) * math.sin(destinationDec),
        );
    return (
      raDeg: (_toDeg(destinationRa) + 360) % 360,
      decDeg: _toDeg(destinationDec),
    );
  }

  /// FOV 필터링용 사진축 각오프셋.
  static TangentPlaneOffset tangentPlaneOffsetDeg({
    required double centerRaDeg,
    required double centerDecDeg,
    required double targetRaDeg,
    required double targetDecDeg,
    required double rotationDeg,
    double parity = 1.0,
    double? pixelScaleArcsec,
    bool rasterCalibration = false,
  }) {
    final iwc = tangentIwcDeg(
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
    );
    if (iwc.xDeg.isNaN || iwc.yDeg.isNaN) return iwc;

    final scale = (pixelScaleArcsec != null && pixelScaleArcsec > 0)
        ? pixelScaleArcsec
        : 1.0;
    final cd = rasterCalibration
        ? rasterCalibrationCdMatrix(
            pixelScaleArcsec: scale,
            orientationDeg: rotationDeg,
            parity: parity,
          )
        : cdMatrix(
            pixelScaleArcsec: scale,
            orientationDeg: rotationDeg,
            parity: parity,
          );
    final det = cd.cd11 * cd.cd22 - cd.cd12 * cd.cd21;
    if (det.abs() < 1e-30) return iwc;

    final inv11 = cd.cd22 / det;
    final inv12 = -cd.cd12 / det;
    final inv21 = -cd.cd21 / det;
    final inv22 = cd.cd11 / det;
    final u = inv11 * iwc.xDeg + inv12 * iwc.yDeg;
    final v = inv21 * iwc.xDeg + inv22 * iwc.yDeg;
    final degPerPix = scale / 3600.0;
    return TangentPlaneOffset(u * degPerPix, v * degPerPix);
  }

  @Deprecated('Use worldToPixel')
  static PixelOffset toPixel({
    required TangentPlaneOffset offset,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (fovWidthDeg <= 0 || fovHeightDeg <= 0) {
      return PixelOffset(imageWidth / 2, imageHeight / 2);
    }
    if (offset.xDeg.isNaN || offset.yDeg.isNaN) {
      return PixelOffset(imageWidth / 2, imageHeight / 2);
    }
    final x = imageWidth / 2 + (offset.xDeg / fovWidthDeg) * imageWidth;
    final y = imageHeight / 2 + (offset.yDeg / fovHeightDeg) * imageHeight;
    return PixelOffset(x, y);
  }

  static double confidence(
    double angularDistanceDeg,
    double fovWidthDeg,
    double fovHeightDeg,
  ) {
    final halfDiagonal = math.sqrt(
      math.pow(fovWidthDeg / 2, 2) + math.pow(fovHeightDeg / 2, 2),
    );
    if (halfDiagonal <= 0) return 0;
    return (1 - angularDistanceDeg / halfDiagonal).clamp(0.0, 1.0).toDouble();
  }
}
