import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/models/catalog_object.dart';
import '../data/models/photo_overlay_object.dart';
import '../data/models/plate_solve_result.dart';
import '../data/models/shooting_record.dart';
import '../data/repositories/catalog_repository.dart';
import 'app_logger.dart';
import 'celestial_position_service.dart';
import 'plate_solve/fits_wcs_parser.dart';
import 'plate_solve_projection.dart';

/// Overlay를 계산할 수 없는 이유 (UI에서 안내 메시지 분기에 사용).
enum PhotoOverlayUnavailableReason {
  noPlateSolve,
  noImageSize,
  error,
}

class PhotoOverlayResult {
  const PhotoOverlayResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.objects,
    this.unavailableReason,
  });

  const PhotoOverlayResult.unavailable(PhotoOverlayUnavailableReason reason)
      : imageWidth = 0,
        imageHeight = 0,
        objects = const [],
        unavailableReason = reason;

  final int imageWidth;
  final int imageHeight;
  final List<PhotoOverlayObject> objects;
  final PhotoOverlayUnavailableReason? unavailableReason;

  bool get isAvailable => unavailableReason == null;
}

/// Plate Solve WCS + Catalog → 사진 Overlay 픽셀 좌표.
class PhotoOverlayService {
  PhotoOverlayService(this._catalogRepository);

  final CatalogRepository _catalogRepository;

  static const _tag = 'PhotoOverlayService';

  Future<PhotoOverlayResult> buildOverlay(ShootingRecord record) async {
    try {
      final plate = record.plateSolve;
      if (plate == null || !plate.success) {
        return const PhotoOverlayResult.unavailable(
          PhotoOverlayUnavailableReason.noPlateSolve,
        );
      }

      final centerRa = plate.centerRa;
      final centerDec = plate.centerDec;
      final fovWidth = plate.fovWidth;
      final fovHeight = plate.fovHeight;
      if (centerRa == null ||
          centerDec == null ||
          fovWidth == null ||
          fovHeight == null) {
        return const PhotoOverlayResult.unavailable(
          PhotoOverlayUnavailableReason.noPlateSolve,
        );
      }

      // Plate/EXIF 해상도를 우선 사용 — 파일 decode probe는 비싸므로 최후 수단.
      var imageWidth = plate.imageWidth ?? record.exif?.imageWidth;
      var imageHeight = plate.imageHeight ?? record.exif?.imageHeight;
      final inferredSize = inferImageDimensions(plate);
      imageWidth ??= inferredSize?.$1;
      imageHeight ??= inferredSize?.$2;
      if (imageWidth == null ||
          imageHeight == null ||
          imageWidth <= 0 ||
          imageHeight <= 0) {
        final fileSize = await _probeImageSize(record.photoUri);
        imageWidth = fileSize?.$1;
        imageHeight = fileSize?.$2;
      }
      if (imageWidth == null ||
          imageHeight == null ||
          imageWidth <= 0 ||
          imageHeight <= 0) {
        return const PhotoOverlayResult.unavailable(
          PhotoOverlayUnavailableReason.noImageSize,
        );
      }

      final rotationDeg = plate.rotation ?? 0.0;
      final parity = _resolveParity(plate);
      final pixelScale = plate.pixelScale;
      var wcs = _resolveWcs(plate);

      // plate solve 해상도 ≠ 파일 해상도면 WCS 스케일
      final solveW = plate.imageWidth;
      final solveH = plate.imageHeight;
      if (wcs != null &&
          solveW != null &&
          solveH != null &&
          solveW > 0 &&
          solveH > 0 &&
          (solveW != imageWidth || solveH != imageHeight)) {
        wcs = wcs.scaleToOriginal(
          uploadWidth: solveW.toDouble(),
          uploadHeight: solveH.toDouble(),
          originalWidth: imageWidth.toDouble(),
          originalHeight: imageHeight.toDouble(),
        );
        _log(
          'WCS scaled solve=${solveW}x$solveH → file=${imageWidth}x$imageHeight',
        );
      }

      _log(
        'buildOverlay center=($centerRa,$centerDec) '
        'orient=$rotationDeg parity=$parity scale=$pixelScale '
        'size=${imageWidth}x$imageHeight hasWcs=${wcs != null}',
      );
      if (wcs != null) {
        _log(
          'WCS CRVAL=(${wcs.crval1},${wcs.crval2}) '
          'CRPIX=(${wcs.crpix1},${wcs.crpix2}) '
          'CD=[${wcs.cd11},${wcs.cd12};${wcs.cd21},${wcs.cd22}]',
        );
      }

      final candidates = await _catalogRepository.findObjectsInPhotoField(
        centerRaDeg: centerRa,
        centerDecDeg: centerDec,
        fovWidthDeg: fovWidth,
        fovHeightDeg: fovHeight,
        rotationDeg: rotationDeg,
      );

      final targetObject =
          await _catalogRepository.getById(record.celestialObjectId);
      final targetPrimaryId =
          targetObject?.effectivePrimaryId ?? record.celestialObjectId;

      final objects = <PhotoOverlayObject>[
        for (final candidate in candidates)
          _toOverlayObject(
            candidate: candidate,
            photoId: record.id,
            centerRa: centerRa,
            centerDec: centerDec,
            fovWidth: fovWidth,
            fovHeight: fovHeight,
            rotationDeg: rotationDeg,
            parity: parity,
            pixelScale: pixelScale,
            wcs: wcs,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            targetPrimaryId: targetPrimaryId,
          ),
      ];

      objects.sort((a, b) {
        if (a.isTarget == b.isTarget) return 0;
        return a.isTarget ? -1 : 1;
      });

      return PhotoOverlayResult(
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        objects: objects,
      );
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return const PhotoOverlayResult.unavailable(
        PhotoOverlayUnavailableReason.error,
      );
    }
  }

  PhotoOverlayObject _toOverlayObject({
    required CatalogObject candidate,
    required String photoId,
    required double centerRa,
    required double centerDec,
    required double fovWidth,
    required double fovHeight,
    required double rotationDeg,
    required double parity,
    required double? pixelScale,
    required FitsWcsHeader? wcs,
    required int imageWidth,
    required int imageHeight,
    required String targetPrimaryId,
  }) {
    final raDeg = CelestialPositionService.parseRaHours(candidate.ra) * 15;
    final decDeg = CelestialPositionService.parseDecDeg(candidate.dec);

    final pixel = PlateSolveProjection.worldToPixel(
      centerRaDeg: centerRa,
      centerDecDeg: centerDec,
      targetRaDeg: raDeg,
      targetDecDeg: decDeg,
      orientationDeg: rotationDeg,
      pixelScaleArcsec: pixelScale ?? 1.0,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      parity: parity,
      wcs: wcs,
    );

    final isTarget = candidate.effectivePrimaryId == targetPrimaryId;
    final nameKey = candidate.displayName.toUpperCase().replaceAll(' ', '');
    if (isTarget ||
        nameKey.contains('M22') ||
        nameKey.contains('IC1290')) {
      _logVerify(
        name: candidate.displayName,
        catalogRa: raDeg,
        catalogDec: decDeg,
        centerRa: centerRa,
        centerDec: centerDec,
        pixelX: pixel.x,
        pixelY: pixel.y,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }

    final axes = _resolveAngularAxesArcmin(candidate);
    final scaleForSize = pixelScale ??
        (imageWidth > 0 ? fovWidth * 3600.0 / imageWidth : null);
    final majorPx = _arcminToPixelRadius(
      axes.major,
      pixelScaleArcsec: scaleForSize,
      fovWidthDeg: fovWidth,
      imageWidth: imageWidth,
    );
    final minorPx = _arcminToPixelRadius(
      axes.minor,
      pixelScaleArcsec: scaleForSize,
      fovWidthDeg: fovWidth,
      imageWidth: imageWidth,
    );

    return PhotoOverlayObject(
      id: candidate.id,
      photoId: photoId,
      catalogId: candidate.id,
      name: candidate.displayName,
      commonName: candidate.displayCommonName,
      objectType: candidate.displayType,
      ra: raDeg,
      dec: decDeg,
      pixelX: pixel.x,
      pixelY: pixel.y,
      angularSizeMajor: axes.major,
      angularSizeMinor: axes.minor,
      rangeRadiusMajorPixel: majorPx,
      rangeRadiusMinorPixel: minorPx ?? majorPx,
      isTarget: isTarget,
    );
  }

  void _logVerify({
    required String name,
    required double catalogRa,
    required double catalogDec,
    required double centerRa,
    required double centerDec,
    required double pixelX,
    required double pixelY,
    required int imageWidth,
    required int imageHeight,
  }) {
    final displayX = pixelX; // source == display after BoxFit.contain box
    final displayY = pixelY;
    _log(
      'VERIFY[$name]\n'
      '  Catalog RA/Dec: $catalogRa, $catalogDec\n'
      '  Image center RA/Dec: $centerRa, $centerDec\n'
      '  Calculated Pixel X/Y: $pixelX, $pixelY '
      '(of ${imageWidth}x$imageHeight)\n'
      '  Displayed Overlay X/Y (source space): $displayX, $displayY',
    );
  }

  static void _log(String message) {
    AppLogger.info(_tag, message);
    debugPrint('[$_tag] $message');
  }

  static FitsWcsHeader? _resolveWcs(PlateSolveResult plate) {
    if (plate.wcs != null && plate.wcs!.isValid) return plate.wcs;
    final raw = plate.rawWcsJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final fits = map['fits_wcs'];
      if (fits is Map<String, dynamic>) {
        return FitsWcsHeader.fromJson(fits);
      }
    } catch (_) {}
    return null;
  }

  static double _resolveParity(PlateSolveResult wcs) {
    final direct = wcs.parity;
    if (direct != null && direct != 0) return direct >= 0 ? 1.0 : -1.0;
    final raw = wcs.rawWcsJson;
    if (raw != null && raw.isNotEmpty) {
      final match = RegExp(r'"parity"\s*:\s*(-?[0-9.]+)').firstMatch(raw);
      if (match != null) {
        final v = double.tryParse(match.group(1)!);
        if (v != null && v != 0) return v >= 0 ? 1.0 : -1.0;
      }
    }
    return 1.0;
  }

  static Future<(int, int)?> _probeImageSize(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return null;
      }
      return (decoded.width, decoded.height);
    } catch (_) {
      return null;
    }
  }

  /// Recovers the source pixel dimensions carried implicitly by the durable
  /// backend result. TC-Backend defines field width/height in degrees and
  /// pixel scale in arcseconds per pixel (`field = scale * pixels / 3600`).
  @visibleForTesting
  static (int, int)? inferImageDimensions(PlateSolveResult plate) {
    final scale = plate.pixelScale;
    final widthDeg = plate.fovWidth;
    final heightDeg = plate.fovHeight;
    if (scale == null ||
        widthDeg == null ||
        heightDeg == null ||
        !scale.isFinite ||
        !widthDeg.isFinite ||
        !heightDeg.isFinite ||
        scale <= 0 ||
        widthDeg <= 0 ||
        heightDeg <= 0) {
      return null;
    }
    final width = (widthDeg * 3600.0 / scale).round();
    final height = (heightDeg * 3600.0 / scale).round();
    return width > 0 && height > 0 ? (width, height) : null;
  }

  static ({double? major, double? minor}) _resolveAngularAxesArcmin(
    CatalogObject candidate,
  ) {
    if (candidate.majorAxis != null && candidate.majorAxis! > 0) {
      return (
        major: candidate.majorAxis,
        minor: (candidate.minorAxis != null && candidate.minorAxis! > 0)
            ? candidate.minorAxis
            : candidate.majorAxis,
      );
    }
    final parsed = _parseAngularSizeArcmin(candidate.angularSize);
    if (parsed != null) return parsed;
    return (major: null, minor: null);
  }

  static ({double major, double minor})? _parseAngularSizeArcmin(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw
        .replaceAll('×', 'x')
        .replaceAll('X', 'x')
        .replaceAll('−', '-');
    final parts = normalized.split('x');

    double? parseOne(String part) {
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(part);
      if (match == null) return null;
      final value = double.tryParse(match.group(1)!) ?? 0;
      if (value <= 0) return null;
      final lower = part.toLowerCase();
      if (lower.contains('°') ||
          lower.contains('º') ||
          lower.contains('deg')) {
        return value * 60;
      }
      if (lower.contains('″') ||
          lower.contains('arcsec') ||
          part.contains('"')) {
        return value / 60;
      }
      return value;
    }

    final first = parseOne(parts.first);
    if (first == null) return null;
    final second = parts.length > 1 ? parseOne(parts[1]) : first;
    return (major: first, minor: second ?? first);
  }

  static double? _arcminToPixelRadius(
    double? arcmin, {
    double? pixelScaleArcsec,
    required double fovWidthDeg,
    required int imageWidth,
  }) {
    if (arcmin == null || arcmin <= 0 || imageWidth <= 0) return null;
    final diameterDeg = arcmin / 60.0;
    if (pixelScaleArcsec != null && pixelScaleArcsec > 0) {
      return (diameterDeg * 3600.0 / pixelScaleArcsec) / 2.0;
    }
    if (fovWidthDeg <= 0) return null;
    return (diameterDeg / fovWidthDeg) * imageWidth / 2.0;
  }
}
