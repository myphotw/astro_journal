import 'dart:io';

import 'package:native_exif/native_exif.dart';
import 'package:path/path.dart' as p;

import '../data/models/exif_info.dart';
import 'app_logger.dart';
import 'seestar_json_parser.dart';

/// 사진 파일에서 EXIF 메타데이터를 추출한다.
///
/// 추출 항목:
///   - Make / Model → equipment
///   - DateTimeOriginal → date
///   - GPSLatitude / GPSLongitude → lat, lng
///   - ExposureTime → exposure (Seestar: 총 적분시간, 1장 노출 아님)
///   - FNumber → fstop
///   - ISOSpeedRatings → iso
///   - FocalLength → focal
///   - PixelXDimension / ImageWidth → imageWidth
///   - PixelYDimension / ImageLength → imageHeight
///   - OwnerName → ownerNameJson (Seestar JSON 원본)
class ExifService {
  Future<ExifInfo> extractFromPath(
    String path, {
    String? originalFilename,
  }) async {
    final displayName = originalFilename ?? p.basename(path);
    AppLogger.metadata('ExifService', '추출 시작: $displayName');
    Exif? exif;
    try {
      exif = await Exif.fromPath(path);

      final date = await _readDate(exif);
      final latLong = await _readLatLong(exif);
      final equipment = await _readEquipment(exif);
      final exposure = await _readExposure(exif);
      final iso = await _readIso(exif);
      final fstop = await _readFstop(exif);
      final focal = await _readFocal(exif);
      final imageSize = await _readImageSize(exif);
      final ownerNameJson = await _readOwnerName(exif);
      final makerNoteJson = await _readMakerNote(exif);
      final file = File(path);
      final filename = displayName;
      final size = file.existsSync()
          ? _formatFileSize(file.lengthSync())
          : '';

      final resolution = (imageSize.$1 != null && imageSize.$2 != null)
          ? '${imageSize.$1} × ${imageSize.$2}'
          : '';

      AppLogger.metadata(
        'ExifService',
        '완료 — 장비=${equipment.isNotEmpty ? equipment : "없음"}, '
            '날짜=${date.isNotEmpty ? date : "없음"}, '
            'GPS=${latLong != null ? "${latLong.latitude.toStringAsFixed(4)}, ${latLong.longitude.toStringAsFixed(4)}" : "없음"}, '
            'MakerNote=${makerNoteJson != null ? "있음" : "없음"}, '
            'OwnerName=${ownerNameJson != null ? "있음" : "없음"}',
      );

      return ExifInfo(
        filename: filename,
        originalFilename: displayName,
        size: size,
        date: date,
        equipment: equipment,
        focal: focal,
        fstop: fstop,
        exposure: exposure,
        iso: iso,
        resolution: resolution,
        lat: latLong?.latitude,
        lng: latLong?.longitude,
        imageWidth: imageSize.$1,
        imageHeight: imageSize.$2,
        ownerNameJson: ownerNameJson,
        makerNoteJson: makerNoteJson,
      );
    } on FileSystemException catch (error, stack) {
      AppLogger.error('ExifService', error, stack);
      return _empty(path);
    } catch (error, stack) {
      AppLogger.error('ExifService', error, stack);
      return _empty(path);
    } finally {
      await exif?.close();
    }
  }

  Future<String> _readDate(Exif exif) async {
    try {
      final dtOriginal = await exif.getOriginalDate();
      if (dtOriginal != null) return dtOriginal.toIso8601String();

      for (final tag in ['DateTime', 'DateTimeDigitized']) {
        try {
          final dt = await exif.getAttribute(tag) as String?;
          if (dt != null && dt.isNotEmpty) {
            final parsed = _parseExifDateTime(dt);
            if (parsed != null) return parsed.toIso8601String();
          }
        } catch (_) {}
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  Future<ExifLatLong?> _readLatLong(Exif exif) async {
    try {
      return await exif.getLatLong();
    } catch (_) {
      return null;
    }
  }

  Future<String> _readEquipment(Exif exif) async {
    final standardTags = ['Make', 'Model'];
    final standardParts = <String>[];
    for (final tag in standardTags) {
      try {
        final val = await exif.getAttribute(tag) as String?;
        if (val != null && val.isNotEmpty) standardParts.add(val.trim());
      } catch (_) {}
    }
    if (standardParts.isNotEmpty) return standardParts.join(' ').trim();

    final fallbackTags = [
      'CameraModelName',
      'UniqueCameraModel',
      'LensModel',
      'DeviceModelName',
    ];
    for (final tag in fallbackTags) {
      try {
        final val = await exif.getAttribute(tag) as String?;
        if (val != null && val.isNotEmpty) return val.trim();
      } catch (_) {}
    }

    final xmpTags = ['XMP:DeviceManufacturer', 'XMP:DeviceModelName'];
    final xmpParts = <String>[];
    for (final tag in xmpTags) {
      try {
        final val = await exif.getAttribute(tag) as String?;
        if (val != null && val.isNotEmpty) xmpParts.add(val.trim());
      } catch (_) {}
    }
    if (xmpParts.isNotEmpty) return xmpParts.join(' ').trim();

    return '';
  }

  Future<String> _readExposure(Exif exif) async {
    final exposureTags = ['ExposureTime', 'ShutterSpeedValue'];
    for (final tag in exposureTags) {
      try {
        final raw = await exif.getAttribute(tag) as String?;
        if (raw != null && raw.isNotEmpty) {
          final formatted = _formatExposureTime(raw);
          if (formatted.isNotEmpty) return formatted;
        }
      } catch (_) {}
    }
    return '';
  }

  Future<String> _readIso(Exif exif) async {
    final isoTags = ['ISOSpeedRatings', 'PhotographicSensitivity', 'ISO'];
    for (final tag in isoTags) {
      try {
        final raw = await exif.getAttribute(tag);
        if (raw == null) continue;
        final parsed = _parseIntFromRaw(raw.toString());
        if (parsed != null && parsed > 0) return 'ISO $parsed';
      } catch (_) {}
    }
    return '';
  }

  Future<String> _readFstop(Exif exif) async {
    final fstopTags = ['FNumber', 'ApertureValue'];
    for (final tag in fstopTags) {
      try {
        final raw = await exif.getAttribute(tag);
        if (raw == null) continue;
        final parsed = _parseRational(raw.toString());
        if (parsed != null && parsed > 0) {
          final formatted = parsed == parsed.roundToDouble()
              ? parsed.toStringAsFixed(0)
              : parsed.toStringAsFixed(1);
          return 'f/$formatted';
        }
      } catch (_) {}
    }
    return '';
  }

  Future<String> _readFocal(Exif exif) async {
    final focalTags = ['FocalLength', 'FocalLengthIn35mmFilm'];
    for (final tag in focalTags) {
      try {
        final raw = await exif.getAttribute(tag);
        if (raw == null) continue;
        final parsed = _parseRational(raw.toString());
        if (parsed != null && parsed > 0) {
          final formatted = parsed == parsed.roundToDouble()
              ? parsed.toStringAsFixed(0)
              : parsed.toStringAsFixed(1);
          return '$formatted mm';
        }
      } catch (_) {}
    }
    return '';
  }

  Future<(int?, int?)> _readImageSize(Exif exif) async {
    int? width;
    int? height;
    for (final tag in ['PixelXDimension', 'ImageWidth', 'ExifImageWidth']) {
      try {
        final raw = await exif.getAttribute(tag);
        if (raw != null) {
          width = _parseIntFromRaw(raw.toString());
          if (width != null) break;
        }
      } catch (_) {}
    }
    for (final tag in ['PixelYDimension', 'ImageLength', 'ExifImageHeight']) {
      try {
        final raw = await exif.getAttribute(tag);
        if (raw != null) {
          height = _parseIntFromRaw(raw.toString());
          if (height != null) break;
        }
      } catch (_) {}
    }
    return (width, height);
  }

  Future<String?> _readMakerNote(Exif exif) async {
    try {
      final raw = await exif.getAttribute('MakerNote');
      return _readSeestarJsonFromAttribute(raw, 'MakerNote');
    } catch (e, stack) {
      AppLogger.metadata('ExifService', 'MakerNote Read Fail: $e');
      AppLogger.error('ExifService._readMakerNote', e, stack);
      return null;
    }
  }

  Future<String?> _readOwnerName(Exif exif) async {
    final ownerTags = ['CameraOwnerName', 'OwnerName', 'Artist'];
    for (final tag in ownerTags) {
      try {
        final raw = await exif.getAttribute(tag);
        final json = _readSeestarJsonFromAttribute(raw, tag);
        if (json != null) return json;
      } catch (e, stack) {
        AppLogger.metadata('ExifService', '$tag Read Fail: $e');
        AppLogger.error('ExifService._readOwnerName.$tag', e, stack);
      }
    }
    AppLogger.metadata('ExifService', 'CameraOwnerName Not Found');
    return null;
  }

  /// MakerNote/OwnerName 태그가 비어 있으면 파일에서 다시 읽어 [ExifInfo]를 보강한다.
  Future<ExifInfo> enrichSeestarRawTags(ExifInfo exif, String path) async {
    final needsMakerNote =
        exif.makerNoteJson == null || exif.makerNoteJson!.trim().isEmpty;
    final needsOwnerName =
        exif.ownerNameJson == null || exif.ownerNameJson!.trim().isEmpty;
    if (!needsMakerNote && !needsOwnerName) {
      return exif;
    }

    Exif? handle;
    try {
      handle = await Exif.fromPath(path);
      final makerNote =
          needsMakerNote ? await _readMakerNote(handle) : exif.makerNoteJson;
      final ownerName =
          needsOwnerName ? await _readOwnerName(handle) : exif.ownerNameJson;

      AppLogger.metadata(
        'ExifService',
        'Seestar 재읽기 — MakerNote=${makerNote != null ? "있음" : "없음"}, '
            'OwnerName=${ownerName != null ? "있음" : "없음"}',
      );

      return exif.copyWith(
        makerNoteJson: makerNote ?? exif.makerNoteJson,
        ownerNameJson: ownerName ?? exif.ownerNameJson,
      );
    } catch (e, stack) {
      AppLogger.metadata('ExifService', 'Seestar 재읽기 실패: $e');
      AppLogger.error('ExifService.enrichSeestarRawTags', e, stack);
      return exif;
    } finally {
      await handle?.close();
    }
  }

  String? _readSeestarJsonFromAttribute(dynamic raw, String tagName) {
    if (raw == null) {
      if (tagName == 'MakerNote') {
        AppLogger.metadata('ExifService', 'MakerNote Not Found');
      }
      return null;
    }

    final text = _attributeToString(raw);
    if (text.isEmpty) {
      AppLogger.metadata('ExifService', '$tagName Not Found (empty)');
      return null;
    }

    final jsonBlock = SeestarJsonParser.extractJsonBlock(text);
    if (jsonBlock == null) {
      AppLogger.metadata('ExifService', '$tagName Found (no JSON block)');
      return null;
    }

    AppLogger.metadata(
      'ExifService',
      '$tagName Found (json len=${jsonBlock.length})',
    );
    return jsonBlock;
  }

  String _attributeToString(dynamic raw) {
    if (raw is String) return raw.trim();
    if (raw is List<int>) {
      return String.fromCharCodes(raw).trim();
    }
    if (raw is List) {
      if (raw.isEmpty) return '';
      if (raw.first is int) {
        return String.fromCharCodes(raw.cast<int>()).trim();
      }
    }
    return raw.toString().trim();
  }

  /// EXIF 전체 태그를 dump하여 디버그 로그에 출력한다.
  Future<Map<String, String>> dumpAllAttributes(String path) async {
    Exif? exif;
    final result = <String, String>{};
    try {
      exif = await Exif.fromPath(path);
      AppLogger.metadata('ExifService DUMP', '=== EXIF Raw Dump: ${p.basename(path)} ===');

      final knownTags = [
        'Make', 'Model', 'DateTime', 'DateTimeOriginal', 'DateTimeDigitized',
        'ExposureTime', 'FNumber', 'ISOSpeedRatings', 'ISO',
        'PhotographicSensitivity', 'ShutterSpeedValue', 'ApertureValue',
        'FocalLength', 'FocalLengthIn35mmFilm',
        'LensModel', 'CameraModelName', 'UniqueCameraModel',
        'Software', 'Artist', 'Copyright',
        'ImageWidth', 'ImageLength', 'PixelXDimension', 'PixelYDimension',
        'XResolution', 'YResolution',
        'GPSLatitude', 'GPSLongitude', 'GPSAltitude',
        'GPSTimeStamp', 'GPSDateStamp',
        'XMP:DeviceManufacturer', 'XMP:DeviceModelName',
        'DeviceModelName', 'MakerNote',
        'OwnerName', 'CameraOwnerName',
      ];

      for (final tag in knownTags) {
        try {
          final val = await exif.getAttribute(tag);
          if (val != null) {
            final valStr = val.toString();
            result[tag] = valStr;
            AppLogger.metadata('ExifService DUMP', '  $tag = $valStr');
          } else {
            AppLogger.metadata('ExifService DUMP', '  $tag = (null)');
          }
        } catch (e) {
          AppLogger.metadata('ExifService DUMP', '  $tag = (read error: $e)');
        }
      }
      AppLogger.metadata('ExifService DUMP', '=== EXIF Raw Dump 완료 ===');
    } catch (e) {
      AppLogger.metadata('ExifService DUMP', '실패: $e');
    } finally {
      await exif?.close();
    }
    return result;
  }

  int? _parseIntFromRaw(String raw) {
    final trimmed = raw.trim();
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0].trim());
        final d = double.tryParse(parts[1].trim());
        if (n != null && d != null && d != 0) return (n / d).round();
      }
    }
    final tupleMatch = RegExp(r'\((\d+)(?:[,\s]+(\d+))?\)').firstMatch(trimmed);
    if (tupleMatch != null) {
      final n = double.tryParse(tupleMatch.group(1) ?? '');
      final dStr = tupleMatch.group(2);
      if (n != null) {
        if (dStr != null) {
          final d = double.tryParse(dStr);
          if (d != null && d != 0) return (n / d).round();
        }
        return n.round();
      }
    }
    return null;
  }

  double? _parseRational(String raw) {
    final trimmed = raw.trim();
    final direct = double.tryParse(trimmed);
    if (direct != null) return direct;
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length == 2) {
        final n = double.tryParse(parts[0].trim());
        final d = double.tryParse(parts[1].trim());
        if (n != null && d != null && d != 0) return n / d;
      }
    }
    final tupleMatch =
        RegExp(r'\((\d+(?:\.\d+)?)[,\s]+(\d+(?:\.\d+)?)\)').firstMatch(trimmed);
    if (tupleMatch != null) {
      final n = double.tryParse(tupleMatch.group(1) ?? '');
      final d = double.tryParse(tupleMatch.group(2) ?? '');
      if (n != null && d != null && d != 0) return n / d;
    }
    return null;
  }

  String _formatExposureTime(String raw) {
    try {
      double? seconds;
      if (raw.contains('/')) {
        final parts = raw.split('/');
        if (parts.length == 2) {
          final num = double.tryParse(parts[0].trim());
          final den = double.tryParse(parts[1].trim());
          if (num != null && den != null && den != 0) {
            seconds = num / den;
          }
        }
      } else {
        seconds = double.tryParse(raw.trim());
      }
      if (seconds == null) return raw;
      if (seconds >= 60) {
        final minutes = seconds / 60.0;
        return '${minutes.toStringAsFixed(1)} min';
      } else if (seconds >= 1) {
        return '${seconds.toStringAsFixed(seconds == seconds.roundToDouble() ? 0 : 1)} sec';
      } else if (seconds > 0) {
        final den = (1.0 / seconds).round();
        return '1/$den sec';
      }
      return raw;
    } catch (_) {
      return raw;
    }
  }

  DateTime? _parseExifDateTime(String raw) {
    try {
      final parts = raw.trim().split(' ');
      if (parts.length < 2) return null;
      final dateParts = parts[0].split(':');
      final timeParts = parts[1].split(':');
      if (dateParts.length < 3 || timeParts.length < 2) return null;
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        timeParts.length > 2 ? int.parse(timeParts[2]) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  ExifInfo _empty(String path) {
    return ExifInfo(
      filename: p.basename(path),
      size: '',
      date: '',
      equipment: '',
      focal: '',
      fstop: '',
      exposure: '',
      iso: '',
      resolution: '',
    );
  }
}
