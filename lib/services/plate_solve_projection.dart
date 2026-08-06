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

  /// FITS CD + CRPIX + CRVAL → 표시 픽셀 (0-based, 좌상단 원점).
  ///
  /// FITS는 픽셀 중심이 1-based. 표시 좌표는 `fits - 0.5`.
  static PixelOffset worldToPixelFromWcs({
    required FitsWcsHeader wcs,
    required double targetRaDeg,
    required double targetDecDeg,
  }) {
    final iwc = tangentIwcDeg(
      centerRaDeg: wcs.crval1,
      centerDecDeg: wcs.crval2,
      targetRaDeg: targetRaDeg,
      targetDecDeg: targetDecDeg,
    );
    if (iwc.xDeg.isNaN || iwc.yDeg.isNaN) {
      return PixelOffset(wcs.crpix1 - 0.5, wcs.crpix2 - 0.5);
    }

    final det = wcs.cd11 * wcs.cd22 - wcs.cd12 * wcs.cd21;
    if (det.abs() < 1e-30) {
      return PixelOffset(wcs.crpix1 - 0.5, wcs.crpix2 - 0.5);
    }

    final inv11 = wcs.cd22 / det;
    final inv12 = -wcs.cd12 / det;
    final inv21 = -wcs.cd21 / det;
    final inv22 = wcs.cd11 / det;

    final u = inv11 * iwc.xDeg + inv12 * iwc.yDeg;
    final v = inv21 * iwc.xDeg + inv22 * iwc.yDeg;

    final fitsX = wcs.crpix1 + u;
    final fitsY = wcs.crpix2 + v;
    return PixelOffset(fitsX - 0.5, fitsY - 0.5);
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
      return worldToPixelFromWcs(
        wcs: wcs,
        targetRaDeg: targetRaDeg,
        targetDecDeg: targetDecDeg,
      );
    }

    if (pixelScaleArcsec <= 0 || imageWidth <= 0 || imageHeight <= 0) {
      return PixelOffset(imageWidth / 2.0, imageHeight / 2.0);
    }

    // crpix_center 가정: CRPIX=(W+1)/2,(H+1)/2 (FITS), CRVAL=field center
    final cd = cdMatrix(
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
    final cd = cdMatrix(
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
