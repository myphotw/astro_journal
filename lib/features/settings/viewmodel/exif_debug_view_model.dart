import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/photo_metadata.dart';
import '../../../data/models/seestar_metadata.dart';
import '../../../services/exif_service.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_metadata_pipeline.dart';
import '../../../services/seestar_json_parser.dart';
import '../../../services/seestar_maker_note_parser.dart';
import '../../../services/seestar_owner_name_parser.dart';

/// Seestar 태그(MakerNote / CameraOwnerName) 분석 결과.
class SeestarTagAnalysis {
  const SeestarTagAnalysis({
    required this.raw,
    required this.length,
    required this.preview500,
    required this.jsonExtractSuccess,
    required this.jsonParseSuccess,
    this.parsed,
    this.parseTraceLog = '',
  });

  final String? raw;
  final int length;
  final String preview500;
  final bool jsonExtractSuccess;
  final bool jsonParseSuccess;
  final SeestarMetadata? parsed;
  final String parseTraceLog;

  String formatLonLat() {
    final meta = parsed;
    if (meta?.lat == null || meta?.lng == null) return 'NULL';
    return '[${meta!.lng}, ${meta.lat}]';
  }

  String toLogSection(String title) {
    final buffer = StringBuffer()..writeln('=== $title ===');
    if (raw == null || raw!.isEmpty) {
      buffer.writeln('(없음)');
      return buffer.toString();
    }
    buffer
      ..writeln('length: $length')
      ..writeln('preview: $preview500')
      ..writeln('JSON 추출: ${jsonExtractSuccess ? "성공" : "실패"}')
      ..writeln('JSON Parse: ${jsonParseSuccess ? "성공" : "실패"}');
    if (parseTraceLog.isNotEmpty) {
      buffer
        ..writeln('--- parse() 단계 로그 ---')
        ..writeln(parseTraceLog.trim());
    }
    if (jsonParseSuccess && parsed != null) {
      buffer
        ..writeln('obj_name: ${parsed!.objName ?? "NULL"}')
        ..writeln('stack_num: ${parsed!.stackNum ?? "NULL"}')
        ..writeln('exp_sec: ${parsed!.expSec ?? "NULL"}')
        ..writeln('tot_exp_sec: ${parsed!.totExpSec ?? "NULL"}')
        ..writeln('lon_lat: ${formatLonLat()}')
        ..writeln('creator: ${parsed!.creator ?? "NULL"}')
        ..writeln('date: ${parsed!.date ?? "NULL"}');
    }
    return buffer.toString();
  }
}

/// File.copy 전후 EXIF 비교 한 줄.
class ExifCopyCompareRow {
  const ExifCopyCompareRow({
    required this.label,
    required this.before,
    required this.after,
    required this.status,
  });

  final String label;
  final String? before;
  final String? after;
  final String status;

  String get displayLine => '$label : $status';
}

/// Pipeline 최종 필드 + 출처.
class PipelineFieldRow {
  const PipelineFieldRow({
    required this.label,
    required this.value,
    required this.source,
  });

  final String label;
  final String value;
  final String source;

  String get displayLine =>
      value.isEmpty ? '$label : -' : '$label : $value ($source)';
}

class ExifDebugViewModel extends ChangeNotifier {
  ExifDebugViewModel({
    required ExifService exifService,
    PhotoMetadataPipeline? metadataRunner,
  })  : _exifService = exifService,
        _metadataRunner =
            metadataRunner ?? forDebugImpl(exifService);

  static const _uuid = Uuid();
  static const _makerNoteParser = SeestarMakerNoteParser();
  static const _ownerNameParser = SeestarOwnerNameParser();

  static const exifDisplayTags = [
    'Make',
    'Model',
    'Software',
    'DateTime',
    'DateTimeOriginal',
    'DateTimeDigitized',
    'GPSLatitude',
    'GPSLongitude',
    'ExposureTime',
    'FNumber',
    'ISOSpeedRatings',
    'FocalLength',
    'MakerNote',
    'CameraOwnerName',
    'OwnerName',
    'Artist',
    'UserComment',
    'ImageDescription',
  ];

  final ExifService _exifService;
  final PhotoMetadataPipeline _metadataRunner;
  final _picker = ImagePicker();

  bool isLoading = false;
  String? errorMessage;

  String? originalFilename;
  String? pickedPath;
  String? fileSizeLabel;
  String? copyPath;

  Map<String, String> originalExif = {};
  Map<String, String> dumpAll = {};
  SeestarTagAnalysis? makerNoteAnalysis;
  SeestarTagAnalysis? cameraOwnerAnalysis;
  List<PipelineFieldRow> pipelineFields = [];
  List<ExifCopyCompareRow> copyCompareRows = [];
  PhotoMetadataProcessResult? pipelineResult;
  String pipelineParseTraceLog = '';

  bool get hasData => pickedPath != null;

  Future<void> pickAndAnalyze() async {
    isLoading = true;
    errorMessage = null;
    pipelineParseTraceLog = '';
    notifyListeners();

    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      final beforePath = picked.path;
      final filename = p.basename(beforePath);
      final beforeFile = File(beforePath);
      final sizeBytes =
          beforeFile.existsSync() ? beforeFile.lengthSync() : 0;

      originalExif = await _readRawExifTags(beforePath);
      dumpAll = await _exifService.dumpAllAttributes(beforePath);

      final makerNoteRaw = originalExif['MakerNote'];
      if (makerNoteRaw == null || makerNoteRaw == 'NULL') {
        makerNoteAnalysis = const SeestarTagAnalysis(
          raw: null,
          length: 0,
          preview500: '',
          jsonExtractSuccess: false,
          jsonParseSuccess: false,
        );
      } else {
        final makerParseLog = StringBuffer();
        final parsed = _makerNoteParser.parse(
          makerNoteRaw,
          analysisLog: makerParseLog,
        );
        makerNoteAnalysis = _analyzeSeestarTag(
          makerNoteRaw,
          parsed,
          parseTraceLog: makerParseLog.toString(),
        );
      }

      final ownerRaw = _firstNonNullTag(
        originalExif,
        ['CameraOwnerName', 'OwnerName', 'Artist'],
      );
      if (ownerRaw == null) {
        cameraOwnerAnalysis = const SeestarTagAnalysis(
          raw: null,
          length: 0,
          preview500: '',
          jsonExtractSuccess: false,
          jsonParseSuccess: false,
        );
      } else {
        final ownerParseLog = StringBuffer();
        final parsed = _ownerNameParser.parse(
          ownerRaw,
          analysisLog: ownerParseLog,
        );
        cameraOwnerAnalysis = _analyzeSeestarTag(
          ownerRaw,
          parsed,
          parseTraceLog: ownerParseLog.toString(),
        );
      }

      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(p.join(appDir.path, 'photos'));
      if (!photosDir.existsSync()) {
        photosDir.createSync(recursive: true);
      }

      final id = _uuid.v4();
      final ext = p.extension(beforePath).toLowerCase();
      final localPath = p.join(photosDir.path, '$id$ext');
      await File(beforePath).copy(localPath);

      final afterTags = await _readCompareTags(localPath);
      final beforeCompareTags = await _readCompareTags(beforePath);
      copyCompareRows = _buildCopyCompare(beforeCompareTags, afterTags);

      final exifInfo = await _exifService.extractFromPath(
        localPath,
        originalFilename: filename,
      );
      final pipelineParseLog = StringBuffer();
      pipelineResult = await _metadataRunner.process(
        exif: exifInfo,
        originalFilename: filename,
        imagePath: localPath,
        parseAnalysisLog: pipelineParseLog,
      );
      pipelineParseTraceLog = pipelineParseLog.toString();
      pipelineFields = _buildPipelineFields(pipelineResult!);

      originalFilename = filename;
      pickedPath = beforePath;
      fileSizeLabel = _formatFileSize(sizeBytes);
      copyPath = localPath;
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  String dumpAllJsonPretty() {
    if (dumpAll.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(dumpAll);
  }

  String buildFullLog() {
    final buffer = StringBuffer();

    buffer.writeln('=== EXIF Debug Log ===');
    if (originalFilename != null) {
      buffer
        ..writeln('원본 파일명: $originalFilename')
        ..writeln('picked.path: $pickedPath')
        ..writeln('파일 크기: $fileSizeLabel')
        ..writeln('복사 전 경로: $pickedPath')
        ..writeln('복사 후 경로: $copyPath');
    }

    buffer.writeln('\n=== 원본 EXIF ===');
    for (final tag in exifDisplayTags) {
      buffer.writeln('$tag: ${originalExif[tag] ?? "NULL"}');
    }

    buffer
      ..writeln('\n=== dumpAllAttributes ===')
      ..writeln(dumpAllJsonPretty());

    if (makerNoteAnalysis != null) {
      buffer.writeln('\n${makerNoteAnalysis!.toLogSection("MakerNote")}');
    }
    if (cameraOwnerAnalysis != null) {
      buffer.writeln('\n${cameraOwnerAnalysis!.toLogSection("CameraOwnerName")}');
    }

    buffer.writeln('\n=== PhotoMetadata Pipeline ===');
    for (final row in pipelineFields) {
      buffer.writeln(row.displayLine);
    }
    if (pipelineParseTraceLog.isNotEmpty) {
      buffer
        ..writeln('\n--- Pipeline parse() 단계 로그 ---')
        ..writeln(pipelineParseTraceLog.trim());
    }

    buffer.writeln('\n=== File.copy 비교 ===');
    for (final row in copyCompareRows) {
      buffer.writeln(row.displayLine);
    }

    return buffer.toString();
  }

  SeestarTagAnalysis _analyzeSeestarTag(
    String raw,
    SeestarMetadata? parsed, {
    String parseTraceLog = '',
  }) {
    final jsonBlock = SeestarJsonParser.extractJsonBlock(raw);
    final extractOk = jsonBlock != null;
    final parseOk = parsed != null;
    final preview = raw.length <= 500 ? raw : raw.substring(0, 500);
    return SeestarTagAnalysis(
      raw: raw,
      length: raw.length,
      preview500: preview,
      jsonExtractSuccess: extractOk,
      jsonParseSuccess: parseOk,
      parsed: parsed,
      parseTraceLog: parseTraceLog,
    );
  }

  String? _firstNonNullTag(Map<String, String> tags, List<String> keys) {
    for (final key in keys) {
      final value = tags[key];
      if (value != null && value != 'NULL' && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Future<Map<String, String>> _readRawExifTags(String path) async {
    Exif? exif;
    final result = <String, String>{};
    try {
      exif = await Exif.fromPath(path);

      for (final tag in exifDisplayTags) {
        if (tag == 'GPSLatitude' || tag == 'GPSLongitude') {
          continue;
        }
        try {
          final raw = await exif.getAttribute(tag);
          result[tag] = _formatRawValue(raw);
        } catch (_) {
          result[tag] = 'NULL';
        }
      }

      try {
        final latLong = await exif.getLatLong();
        if (latLong != null) {
          result['GPSLatitude'] = latLong.latitude.toStringAsFixed(8);
          result['GPSLongitude'] = latLong.longitude.toStringAsFixed(8);
        } else {
          result['GPSLatitude'] = _formatRawValue(
            await exif.getAttribute('GPSLatitude'),
          );
          result['GPSLongitude'] = _formatRawValue(
            await exif.getAttribute('GPSLongitude'),
          );
        }
      } catch (_) {
        result['GPSLatitude'] = 'NULL';
        result['GPSLongitude'] = 'NULL';
      }
    } catch (_) {
      for (final tag in exifDisplayTags) {
        result[tag] = 'NULL';
      }
    } finally {
      await exif?.close();
    }
    return result;
  }

  Future<Map<String, String?>> _readCompareTags(String path) async {
    Exif? exif;
    final result = <String, String?>{};
    try {
      exif = await Exif.fromPath(path);

      for (final tag in ['MakerNote', 'CameraOwnerName', 'DateTimeOriginal']) {
        try {
          final raw = await exif.getAttribute(tag);
          final text = _rawToString(raw);
          result[tag] = text.isEmpty ? null : text;
        } catch (_) {
          result[tag] = null;
        }
      }

      if (result['CameraOwnerName'] == null) {
        for (final tag in ['OwnerName', 'Artist']) {
          try {
            final raw = await exif.getAttribute(tag);
            final text = _rawToString(raw);
            if (text.isNotEmpty) {
              result['CameraOwnerName'] = text;
              break;
            }
          } catch (_) {}
        }
      }

      try {
        final latLong = await exif.getLatLong();
        if (latLong != null) {
          result['GPS'] =
              '${latLong.latitude.toStringAsFixed(6)}, ${latLong.longitude.toStringAsFixed(6)}';
        } else {
          result['GPS'] = null;
        }
      } catch (_) {
        result['GPS'] = null;
      }
    } catch (_) {
      result['MakerNote'] = null;
      result['CameraOwnerName'] = null;
      result['GPS'] = null;
      result['DateTimeOriginal'] = null;
    } finally {
      await exif?.close();
    }
    return result;
  }

  List<ExifCopyCompareRow> _buildCopyCompare(
    Map<String, String?> before,
    Map<String, String?> after,
  ) {
    const labels = {
      'MakerNote': 'MakerNote',
      'CameraOwnerName': 'CameraOwnerName',
      'GPS': 'GPS',
      'DateTimeOriginal': 'Date',
    };

    return labels.entries.map((entry) {
      final b = before[entry.key];
      final a = after[entry.key];
      final hadBefore = b != null && b.isNotEmpty;
      final hasAfter = a != null && a.isNotEmpty;

      String status;
      if (!hadBefore && !hasAfter) {
        status = '동일 (없음)';
      } else if (hadBefore && !hasAfter) {
        status = '사라짐';
      } else if (!hadBefore && hasAfter) {
        status = '추가됨';
      } else if (b == a) {
        status = '동일';
      } else {
        status = '변경';
      }

      return ExifCopyCompareRow(
        label: entry.value,
        before: b,
        after: a,
        status: status,
      );
    }).toList();
  }

  List<PipelineFieldRow> _buildPipelineFields(
    PhotoMetadataProcessResult result,
  ) {
    final exif = result.exifInfo;
    final meta = result.metadata;

    String dateValue = exif.date.isNotEmpty
        ? MetadataFormat.formatDateTimeInput(exif.date)
        : '-';
    if (dateValue.isEmpty) dateValue = '-';

    String gpsValue = '-';
    if (exif.lat != null && exif.lng != null) {
      gpsValue =
          '${exif.lat!.toStringAsFixed(6)}, ${exif.lng!.toStringAsFixed(6)}';
    }

    return [
      _field('Target', exif.targetName ?? '-', meta.targetNameSource),
      _field('Date', dateValue, meta.capturedAtSource),
      _field(
        'Equipment',
        exif.equipment.isNotEmpty ? exif.equipment : '-',
        meta.equipmentSource,
      ),
      _field('GPS', gpsValue, meta.gpsSource),
      _field(
        'StackNum',
        exif.stackNum?.toString() ?? '-',
        meta.stackNumSource,
      ),
      _field(
        'ExpSec',
        exif.singleExpSec ?? '-',
        meta.singleExpSecSource,
      ),
      _field(
        'TotExpSec',
        exif.exposure.isNotEmpty ? exif.exposure : '-',
        meta.exposureSource,
      ),
      _field('ISO', exif.iso.isNotEmpty ? exif.iso : '-', meta.isoSource),
      _field(
        'FStop',
        exif.fstop.isNotEmpty ? exif.fstop : '-',
        meta.fstopSource,
      ),
      _field(
        'Focal',
        exif.focal.isNotEmpty ? exif.focal : '-',
        meta.focalSource,
      ),
    ];
  }

  PipelineFieldRow _field(
    String label,
    String value,
    MetadataSource? source,
  ) {
    return PipelineFieldRow(
      label: label,
      value: value,
      source: source?.badgeLabel ?? '-',
    );
  }

  String _formatRawValue(dynamic raw) {
    if (raw == null) return 'NULL';
    final text = _rawToString(raw);
    return text.isEmpty ? 'NULL' : text;
  }

  String _rawToString(dynamic raw) {
    if (raw is String) return raw.trim();
    if (raw is List<int>) return String.fromCharCodes(raw);
    if (raw is List && raw.isNotEmpty && raw.first is int) {
      return String.fromCharCodes(raw.cast<int>());
    }
    return raw.toString().trim();
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB ($bytes bytes)';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB ($bytes bytes)';
    }
    return '$bytes B';
  }
}
