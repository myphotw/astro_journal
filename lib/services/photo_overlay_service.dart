import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/constants/catalog_object_metadata_overrides.dart';
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
enum PhotoOverlayUnavailableReason { noPlateSolve, noImageSize, error }

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

typedef PhotoOverlayExifOrientationReader = Future<int?> Function(String path);

/// Plate Solve WCS + Catalog → 사진 Overlay 픽셀 좌표.
class PhotoOverlayService {
  PhotoOverlayService(
    this._catalogRepository, {
    PhotoOverlayExifOrientationReader? exifOrientationReader,
  }) : _exifOrientationReader =
           exifOrientationReader ?? _readLocalJpegOrientation;

  final CatalogRepository _catalogRepository;
  final PhotoOverlayExifOrientationReader _exifOrientationReader;

  static const _tag = 'PhotoOverlayService';
  static final Set<String> _wcsDebugLoggedRecordIds = <String>{};

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
      final wcs = _resolveWcs(plate);
      final orientationProbe = wcs == null
          ? const _ExifOrientationProbe.unavailable()
          : await _resolveExifOrientation(record);
      final wcsRasterWidth = wcs?.rasterWidth;
      final wcsRasterHeight = wcs?.rasterHeight;
      final rasterMapping = wcs == null
          ? null
          : _GalleryRasterMapping(
              wcsWidth: wcsRasterWidth != null && wcsRasterWidth > 0
                  ? wcsRasterWidth
                  : imageWidth.toDouble(),
              wcsHeight: wcsRasterHeight != null && wcsRasterHeight > 0
                  ? wcsRasterHeight
                  : imageHeight.toDouble(),
              galleryWidth: imageWidth.toDouble(),
              galleryHeight: imageHeight.toDouble(),
              exifOrientation: orientationProbe.orientation ?? 1,
            );

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

      final targetObject = await _catalogRepository.getById(
        record.celestialObjectId,
      );
      final targetPrimaryId =
          targetObject?.effectivePrimaryId ?? record.celestialObjectId;

      final objects = <PhotoOverlayObject>[];
      for (final candidate in candidates) {
        final overlayObject = _toOverlayObject(
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
          rasterMapping: rasterMapping,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          targetPrimaryId: targetPrimaryId,
        );
        if (overlayObject != null) objects.add(overlayObject);
      }

      objects.sort((a, b) {
        if (a.isTarget == b.isTarget) return 0;
        return a.isTarget ? -1 : 1;
      });

      _logWcsRuntimeOnce(
        record: record,
        plate: plate,
        wcs: wcs,
        rasterMapping: rasterMapping,
        orientationProbe: orientationProbe,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        rotationDeg: rotationDeg,
        parity: parity,
        objects: objects,
      );

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

  PhotoOverlayObject? _toOverlayObject({
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
    required _GalleryRasterMapping? rasterMapping,
    required int imageWidth,
    required int imageHeight,
    required String targetPrimaryId,
  }) {
    final raHours = CelestialPositionService.parseRaHours(candidate.ra);
    final decDeg = CelestialPositionService.parseDecDeg(candidate.dec);
    if (raHours == null || decDeg == null) return null;
    final raDeg = raHours * 15;

    final wcsWidth = rasterMapping?.wcsWidth.round() ?? imageWidth;
    final wcsHeight = rasterMapping?.wcsHeight.round() ?? imageHeight;
    final projectedPixel = PlateSolveProjection.worldToPixel(
      centerRaDeg: centerRa,
      centerDecDeg: centerDec,
      targetRaDeg: raDeg,
      targetDecDeg: decDeg,
      orientationDeg: rotationDeg,
      pixelScaleArcsec: pixelScale ?? 1.0,
      imageWidth: wcsWidth,
      imageHeight: wcsHeight,
      parity: parity,
      wcs: wcs,
    );
    final pixel = rasterMapping?.mapPoint(projectedPixel) ?? projectedPixel;

    final isTarget = candidate.effectivePrimaryId == targetPrimaryId;
    final nameKey = candidate.displayName.toUpperCase().replaceAll(' ', '');
    if (kDebugMode &&
        (isTarget ||
            const {'M31', 'M32', 'M110', 'M8', 'M20'}.contains(nameKey))) {
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
    final scaleForSize =
        pixelScale ?? (imageWidth > 0 ? fovWidth * 3600.0 / imageWidth : null);
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
    final catalogPositionAngle =
        candidate.positionAngle ??
        CatalogObjectMetadataOverrides.positionAngleDegreesForId(
          candidate.displayName,
        ) ??
        CatalogObjectMetadataOverrides.positionAngleDegreesForId(candidate.id);
    final projectedEllipseRotation = catalogPositionAngle == null
        ? 0.0
        : PlateSolveProjection.positionAngleToPixelRadians(
            centerRaDeg: centerRa,
            centerDecDeg: centerDec,
            targetRaDeg: raDeg,
            targetDecDeg: decDeg,
            positionAngleDeg: catalogPositionAngle,
            orientationDeg: rotationDeg,
            pixelScaleArcsec: pixelScale ?? 1.0,
            imageWidth: wcsWidth,
            imageHeight: wcsHeight,
            parity: parity,
            wcs: wcs,
          );
    final ellipseRotation =
        rasterMapping?.mapAngle(projectedEllipseRotation) ??
        projectedEllipseRotation;

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
      ellipseRotationRadians: ellipseRotation,
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

  static void _logWcsRuntimeOnce({
    required ShootingRecord record,
    required PlateSolveResult plate,
    required FitsWcsHeader? wcs,
    required _GalleryRasterMapping? rasterMapping,
    required _ExifOrientationProbe orientationProbe,
    required int imageWidth,
    required int imageHeight,
    required double rotationDeg,
    required double parity,
    required List<PhotoOverlayObject> objects,
  }) {
    if (!_wcsDebugLoggedRecordIds.add(record.id)) return;

    PhotoOverlayObject? objectFor(String catalogId) {
      final key = catalogId.toUpperCase();
      for (final object in objects) {
        if (object.catalogId.toUpperCase().replaceAll(' ', '') == key ||
            object.name.toUpperCase().replaceAll(' ', '') == key) {
          return object;
        }
      }
      return null;
    }

    final m31 = objectFor('M31');
    String coordinates(String id) {
      final object = objectFor(id);
      if (object == null) return '$id=missing';
      final dx = m31 == null ? double.nan : object.pixelX - m31.pixelX;
      final dy = m31 == null ? double.nan : object.pixelY - m31.pixelY;
      return '$id={ra=${object.ra.toStringAsFixed(6)},'
          'dec=${object.dec.toStringAsFixed(6)},'
          'x=${object.pixelX.toStringAsFixed(2)},'
          'y=${object.pixelY.toStringAsFixed(2)},'
          'dx=${dx.toStringAsFixed(2)},dy=${dy.toStringAsFixed(2)}}';
    }

    final sanitizedRecordId = record.id.replaceAll(
      RegExp(r'[^A-Za-z0-9:_-]'),
      '',
    );
    final safeRecordId = sanitizedRecordId.substring(
      0,
      sanitizedRecordId.length.clamp(0, 48),
    );
    final fullWcs = wcs != null;
    final branch = fullWcs
        ? 'full_wcs/worldToPixelFromWcs'
        : 'scalar_fallback/rasterCalibrationCdMatrix';
    final centerRa = wcs?.crval1 ?? plate.centerRa;
    final centerDec = wcs?.crval2 ?? plate.centerDec;

    // Intentionally not gated by kDebugMode: this one-shot diagnostic must be
    // visible through adb logcat in a release build. It contains no path/token.
    debugPrint(
      '[WCS_DEBUG] record_id=$safeRecordId '
      'intrinsic=${imageWidth}x$imageHeight '
      'hydrated_wcs=${plate.wcs != null} resolved_wcs=$fullWcs '
      'IMAGEW=${wcs?.imageW ?? 'null'} IMAGEH=${wcs?.imageH ?? 'null'} '
      'branch=$branch full_wcs_used=$fullWcs '
      'scalar_fallback_used=${!fullWcs} '
      'fits_to_flutter=${fullWcs ? 'x_identity_y_identity_pixel_center' : 'not_applicable'} '
      'sip_inverse=${wcs?.sipInverseMode ?? 'none'} '
      'wcs_raster=${rasterMapping == null ? "none" : "${rasterMapping.wcsWidth}x${rasterMapping.wcsHeight}"} '
      'gallery_raster=${imageWidth}x$imageHeight '
      'exif_orientation=${orientationProbe.orientation ?? "unknown"} '
      'orientation_source=${orientationProbe.source} '
      'gallery_transform=${rasterMapping?.transformName ?? "none"} '
      'center_ra=$centerRa center_dec=$centerDec '
      'rotation=$rotationDeg parity=$parity '
      '${coordinates('M31')} ${coordinates('M32')} ${coordinates('M110')}',
    );
  }

  static FitsWcsHeader? _resolveWcs(PlateSolveResult plate) {
    if (plate.wcs != null && plate.wcs!.isValid) return plate.wcs;
    final raw = plate.rawWcsJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final fits = map['wcs'] ?? map['fits_wcs'] ?? map['fitsWcs'];
      if (fits is Map) {
        return FitsWcsHeader.fromJson(Map<String, dynamic>.from(fits));
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

  Future<_ExifOrientationProbe> _resolveExifOrientation(
    ShootingRecord record,
  ) async {
    // Gallery detail displays preview_url first. TC-Backend creates that
    // raster with ImageOps.exif_transpose(), while Astrometry solves the
    // unchanged original bytes. Read the actual local original tag when the
    // linked local record is still available; never guess a transform.
    if (record.previewUrl == null || record.previewUrl!.trim().isEmpty) {
      return const _ExifOrientationProbe.unavailable();
    }
    final path = record.photoUri;
    if (path == null || path.isEmpty || _isRemotePath(path)) {
      return const _ExifOrientationProbe.unavailable();
    }
    final orientation = await _exifOrientationReader(path);
    if (orientation == null || orientation < 1 || orientation > 8) {
      return const _ExifOrientationProbe.unavailable();
    }
    return _ExifOrientationProbe(
      orientation: orientation,
      source: 'local_original_exif',
    );
  }

  static bool _isRemotePath(String path) {
    if (path.startsWith('/api/')) return true;
    final scheme = Uri.tryParse(path)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  static Future<int?> _readLocalJpegOrientation(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final exif = img.decodeJpgExif(await file.readAsBytes());
      if (exif == null) return null;
      return exif.imageIfd.orientation ?? 1;
    } catch (_) {
      return null;
    }
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
      if (lower.contains('°') || lower.contains('º') || lower.contains('deg')) {
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

class _ExifOrientationProbe {
  const _ExifOrientationProbe({
    required this.orientation,
    required this.source,
  });

  const _ExifOrientationProbe.unavailable()
    : orientation = null,
      source = 'unavailable';

  final int? orientation;
  final String source;
}

/// Maps the top-left-origin WCS raster into the EXIF-normalized Gallery
/// raster. Coordinates use continuous image edges after the WCS 1-based
/// pixel-center conversion, rather than integer indices.
class _GalleryRasterMapping {
  const _GalleryRasterMapping({
    required this.wcsWidth,
    required this.wcsHeight,
    required this.galleryWidth,
    required this.galleryHeight,
    required this.exifOrientation,
  });

  final double wcsWidth;
  final double wcsHeight;
  final double galleryWidth;
  final double galleryHeight;
  final int exifOrientation;

  bool get _swapsAxes => exifOrientation >= 5 && exifOrientation <= 8;

  double get _orientedWidth => _swapsAxes ? wcsHeight : wcsWidth;
  double get _orientedHeight => _swapsAxes ? wcsWidth : wcsHeight;

  String get transformName => exifOrientation == 1
      ? 'identity_scale'
      : 'exif_${exifOrientation}_then_scale';

  PixelOffset mapPoint(PixelOffset point) {
    final oriented = switch (exifOrientation) {
      2 => PixelOffset(wcsWidth - point.x, point.y),
      3 => PixelOffset(wcsWidth - point.x, wcsHeight - point.y),
      4 => PixelOffset(point.x, wcsHeight - point.y),
      5 => PixelOffset(point.y, point.x),
      6 => PixelOffset(wcsHeight - point.y, point.x),
      7 => PixelOffset(wcsHeight - point.y, wcsWidth - point.x),
      8 => PixelOffset(point.y, wcsWidth - point.x),
      _ => point,
    };
    return PixelOffset(
      oriented.x * galleryWidth / _orientedWidth,
      oriented.y * galleryHeight / _orientedHeight,
    );
  }

  double mapAngle(double angle) {
    final x = math.cos(angle);
    final y = math.sin(angle);
    final oriented = switch (exifOrientation) {
      2 => PixelOffset(-x, y),
      3 => PixelOffset(-x, -y),
      4 => PixelOffset(x, -y),
      5 => PixelOffset(y, x),
      6 => PixelOffset(-y, x),
      7 => PixelOffset(-y, -x),
      8 => PixelOffset(y, -x),
      _ => PixelOffset(x, y),
    };
    return math.atan2(
      oriented.y * galleryHeight / _orientedHeight,
      oriented.x * galleryWidth / _orientedWidth,
    );
  }
}
