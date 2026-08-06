import 'dart:io';

import 'package:native_exif/native_exif.dart';

import 'app_logger.dart';
import 'exif_service.dart';

/// ImagePicker → File.copy 전후 EXIF 비교 진단 (Android 실기기용).
class ExifCopyDiagnostic {
  ExifCopyDiagnostic._();

  static const _compareTags = [
    'MakerNote',
    'CameraOwnerName',
    'OwnerName',
    'Make',
    'Model',
    'DateTimeOriginal',
  ];

  /// [path] 파일의 핵심 태그 + dumpAllAttributes 전체를 Logcat에 출력한다.
  static Future<Map<String, String?>> dumpFile(String path, String stage) async {
    final service = ExifService();
    final file = File(path);
    final size = file.existsSync() ? file.lengthSync() : 0;

    AppLogger.metadata('ExifCopyDiag', '══════════════════════════════════════');
    AppLogger.metadata('ExifCopyDiag', '[$stage] path=$path');
    AppLogger.metadata('ExifCopyDiag', '[$stage] size=$size bytes');

    final keyTags = await _readKeyTags(path, stage);
    for (final tag in _compareTags) {
      final v = keyTags[tag];
      AppLogger.metadata(
        'ExifCopyDiag',
        '[$stage] $tag = ${v ?? "(null)"}',
      );
    }

    final gps = keyTags['GPS'];
    AppLogger.metadata('ExifCopyDiag', '[$stage] GPS = ${gps ?? "(null)"}');

    AppLogger.metadata('ExifCopyDiag', '[$stage] --- dumpAllAttributes() 시작 ---');
    final dump = await service.dumpAllAttributes(path);
    if (dump.isEmpty) {
      AppLogger.metadata('ExifCopyDiag', '[$stage] dumpAllAttributes() = {}');
    } else {
      for (final entry in dump.entries) {
        AppLogger.metadata(
          'ExifCopyDiag',
          '[$stage] dump.${entry.key} = ${entry.value}',
        );
      }
    }
    AppLogger.metadata(
      'ExifCopyDiag',
      '[$stage] dumpAllAttributes() 태그 수 = ${dump.length}',
    );
    AppLogger.metadata('ExifCopyDiag', '[$stage] --- dumpAllAttributes() 완료 ---');

    return keyTags;
  }

  static Future<Map<String, String?>> _readKeyTags(
    String path,
    String stage,
  ) async {
    Exif? exif;
    final result = <String, String?>{};
    try {
      exif = await Exif.fromPath(path);

      for (final tag in _compareTags) {
        try {
          final raw = await exif.getAttribute(tag);
          if (raw == null) {
            result[tag] = null;
            continue;
          }
          final text = _rawToString(raw);
          result[tag] = text.isEmpty ? null : text;

          if (tag == 'MakerNote') {
            final len = text.length;
            final preview = len <= 300 ? text : '${text.substring(0, 300)}...';
            AppLogger.metadata('ExifCopyDiag', '[$stage] MakerNote length = $len');
            AppLogger.metadata('ExifCopyDiag', '[$stage] MakerNote preview = $preview');
          }
        } catch (e) {
          result[tag] = null;
          AppLogger.metadata('ExifCopyDiag', '[$stage] $tag read error: $e');
        }
      }

      try {
        final latLong = await exif.getLatLong();
        if (latLong != null) {
          result['GPS'] =
              '${latLong.latitude.toStringAsFixed(6)}, ${latLong.longitude.toStringAsFixed(6)}';
        } else {
          final lat = await exif.getAttribute('GPSLatitude');
          final lng = await exif.getAttribute('GPSLongitude');
          if (lat != null && lng != null) {
            result['GPS'] = '$lat, $lng';
          }
        }
      } catch (_) {
        result['GPS'] = null;
      }
    } catch (e) {
      AppLogger.metadata('ExifCopyDiag', '[$stage] Exif.fromPath 실패: $e');
    } finally {
      await exif?.close();
    }
    return result;
  }

  static String _rawToString(dynamic raw) {
    if (raw is String) return raw;
    if (raw is List<int>) return String.fromCharCodes(raw);
    if (raw is List && raw.isNotEmpty && raw.first is int) {
      return String.fromCharCodes(raw.cast<int>());
    }
    return raw.toString();
  }

  /// picked.path vs UUID 복사본 비교.
  static void compare(
    Map<String, String?> before,
    Map<String, String?> after,
  ) {
    AppLogger.metadata('ExifCopyDiag', '══════════════════════════════════════');
    AppLogger.metadata('ExifCopyDiag', '[COMPARE] picked.path vs UUID copy');

    const watch = ['MakerNote', 'CameraOwnerName', 'GPS', 'DateTimeOriginal'];
    final lost = <String>[];

    for (final tag in watch) {
      final b = before[tag];
      final a = after[tag];
      final hadBefore = b != null && b.isNotEmpty;
      final hasAfter = a != null && a.isNotEmpty;

      AppLogger.metadata(
        'ExifCopyDiag',
        '[COMPARE] $tag: before=${hadBefore ? "있음" : "없음"} after=${hasAfter ? "있음" : "없음"}',
      );
      if (hadBefore) {
        AppLogger.metadata('ExifCopyDiag', '[COMPARE] $tag before value = $b');
      }
      if (hasAfter) {
        AppLogger.metadata('ExifCopyDiag', '[COMPARE] $tag after value = $a');
      }

      if (hadBefore && !hasAfter) {
        lost.add(tag);
      } else if (hadBefore && hasAfter && b != a) {
        AppLogger.metadata(
          'ExifCopyDiag',
          '[COMPARE] $tag: 값 변경됨 (File.copy 이후 내용 다름)',
        );
      }
    }

    if (lost.isEmpty) {
      AppLogger.metadata(
        'ExifCopyDiag',
        '[COMPARE] File.copy() 후 사라진 항목: 없음',
      );
    } else {
      AppLogger.metadata(
        'ExifCopyDiag',
        '[COMPARE] File.copy() 후 사라진 항목: ${lost.join(", ")}',
      );
    }
  }

  /// PhotoMetadataPipeline 입력 JSON 필드 로그.
  static void logPipelineJson({
    String? makerNoteJson,
    String? ownerNameJson,
  }) {
    AppLogger.metadata('ExifCopyDiag', '══════════════════════════════════════');
    AppLogger.metadata('ExifCopyDiag', '[Pipeline] makerNoteJson / ownerNameJson');

    if (makerNoteJson == null || makerNoteJson.isEmpty) {
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] makerNoteJson length = 0');
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] makerNoteJson preview = (null)');
    } else {
      final len = makerNoteJson.length;
      final preview = len <= 300
          ? makerNoteJson
          : '${makerNoteJson.substring(0, 300)}...';
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] makerNoteJson length = $len');
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] makerNoteJson preview = $preview');
    }

    if (ownerNameJson == null || ownerNameJson.isEmpty) {
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] ownerNameJson length = 0');
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] ownerNameJson preview = (null)');
    } else {
      final len = ownerNameJson.length;
      final preview = len <= 300
          ? ownerNameJson
          : '${ownerNameJson.substring(0, 300)}...';
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] ownerNameJson length = $len');
      AppLogger.metadata('ExifCopyDiag', '[Pipeline] ownerNameJson preview = $preview');
    }
  }
}
