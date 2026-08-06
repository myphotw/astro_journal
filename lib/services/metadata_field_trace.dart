import 'dart:convert';

import '../data/models/exif_info.dart';
import '../data/models/photo_metadata.dart';
import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';
import 'metadata_format.dart';

/// Parser → Repository → DB → UI 각 단계의 필드 값을 추적한다.
class MetadataFieldTrace {
  MetadataFieldTrace._();

  static void logMakerNoteRaw(String? raw) {
    AppLogger.metadata(
      'Trace.MakerNote',
      'raw=${raw != null && raw.isNotEmpty ? "len=${raw.length}" : "null"}',
    );
  }

  static void logParser(String source, SeestarMetadata? meta) {
    if (meta == null) {
      AppLogger.metadata('Trace.Parser.$source', 'result=null');
      return;
    }
    AppLogger.metadata(
      'Trace.Parser.$source',
      'objName=${meta.objName ?? "-"} date=${meta.date ?? "-"} '
          'lat=${meta.lat?.toStringAsFixed(6) ?? "-"} '
          'lng=${meta.lng?.toStringAsFixed(6) ?? "-"} '
          'stack=${meta.stackNum ?? "-"} exp=${meta.expSec ?? "-"} '
          'tot=${meta.totExpSec ?? "-"} creator=${meta.creator ?? "-"}',
    );
  }

  static void logPhotoMetadata(String stage, PhotoMetadata m) {
    AppLogger.metadata(
      'Trace.$stage.PhotoMetadata',
      'targetName=${m.targetName ?? "-"} capturedAt=${m.capturedAt ?? "-"} '
          'lat=${m.lat?.toStringAsFixed(6) ?? "-"} lng=${m.lng?.toStringAsFixed(6) ?? "-"} '
          'stackNum=${m.stackNum ?? "-"} singleExpSec=${m.singleExpSec ?? "-"} '
          'exposure=${m.exposure ?? "-"} equipment=${m.equipment ?? "-"} '
          'iso=${m.iso ?? "-"} fstop=${m.fstop ?? "-"}',
    );
  }

  static void logExifInfo(String stage, ExifInfo exif) {
    AppLogger.metadata(
      'Trace.$stage.ExifInfo',
      'targetName=${exif.targetName ?? "-"} date=${exif.date.isEmpty ? "-" : exif.date} '
          'lat=${exif.lat?.toStringAsFixed(6) ?? "-"} lng=${exif.lng?.toStringAsFixed(6) ?? "-"} '
          'stackNum=${exif.stackNum ?? "-"} singleExpSec=${exif.singleExpSec ?? "-"} '
          'exposure=${exif.exposure.isEmpty ? "-" : exif.exposure} '
          'equipment=${exif.equipment.isEmpty ? "-" : exif.equipment} '
          'iso=${exif.iso.isEmpty ? "-" : exif.iso} fstop=${exif.fstop.isEmpty ? "-" : exif.fstop}',
    );
  }

  static void logSeestarMerge(String phase, ExifInfo exif) {
    final gps = exif.lat != null && exif.lng != null
        ? '${exif.lat!.toStringAsFixed(6)}, ${exif.lng!.toStringAsFixed(6)}'
        : 'null';

    AppLogger.metadata('SeestarMerge', phase);
    AppLogger.metadata('SeestarMerge', 'Target = ${exif.targetName ?? "null"}');
    AppLogger.metadata(
      'SeestarMerge',
      'Date = ${exif.date.isEmpty ? "null" : exif.date}',
    );
    AppLogger.metadata('SeestarMerge', 'GPS = $gps');
    AppLogger.metadata('SeestarMerge', 'Stack = ${exif.stackNum ?? "null"}');
    AppLogger.metadata(
      'SeestarMerge',
      'Exp = ${exif.singleExpSec ?? "null"}',
    );
    AppLogger.metadata(
      'SeestarMerge',
      'Total = ${exif.exposure.isEmpty ? "null" : exif.exposure}',
    );
  }

  static void logParserDump({
    SeestarMetadata? makerNote,
    SeestarMetadata? ownerName,
    SeestarMetadata? filename,
  }) {
    if (makerNote != null) {
      AppLogger.metadata(
        'SeestarMerge',
        'MakerNote Parser JSON = ${jsonEncode(makerNote.toJson())}',
      );
    }
    if (ownerName != null) {
      AppLogger.metadata(
        'SeestarMerge',
        'CameraOwnerName Parser JSON = ${jsonEncode(ownerName.toJson())}',
      );
    }
    if (filename != null) {
      AppLogger.metadata(
        'SeestarMerge',
        'FileName Parser JSON = ${jsonEncode(filename.toJson())}',
      );
    }
  }

  static bool hasMissingSeestarFields(ExifInfo exif) {
    return exif.targetName == null ||
        exif.date.isEmpty ||
        exif.lat == null ||
        exif.lng == null ||
        exif.stackNum == null ||
        exif.singleExpSec == null ||
        exif.exposure.isEmpty;
  }

  static void logUiValues(String screen, ExifInfo exif) {
    final dateText = exif.date.isNotEmpty
        ? MetadataFormat.formatDateTimeInput(exif.date)
        : '-';
    final gpsText = exif.lat != null && exif.lng != null
        ? '${exif.lat!.toStringAsFixed(6)}, ${exif.lng!.toStringAsFixed(6)}'
        : '-';

    AppLogger.metadata('Trace.UI.$screen', 'Target UI Value = ${exif.targetName ?? "-"}');
    AppLogger.metadata('Trace.UI.$screen', 'Date UI Value = $dateText');
    AppLogger.metadata('Trace.UI.$screen', 'GPS UI Value = $gpsText');
    AppLogger.metadata('Trace.UI.$screen', 'Stack UI Value = ${exif.stackNum ?? "-"}');
    AppLogger.metadata('Trace.UI.$screen', 'Exp UI Value = ${exif.singleExpSec ?? "-"}');
    AppLogger.metadata(
      'Trace.UI.$screen',
      'TotExp UI Value = ${exif.exposure.isNotEmpty ? exif.exposure : "-"}',
    );
    AppLogger.metadata(
      'Trace.UI.$screen',
      'Equipment UI Value = ${exif.equipment.isNotEmpty ? exif.equipment : "-"}',
    );
    AppLogger.metadata(
      'Trace.UI.$screen',
      'ISO UI Value = ${exif.iso.isNotEmpty ? exif.iso : "-"}',
    );
    AppLogger.metadata(
      'Trace.UI.$screen',
      'FStop UI Value = ${exif.fstop.isNotEmpty ? exif.fstop : "-"}',
    );
  }
}
