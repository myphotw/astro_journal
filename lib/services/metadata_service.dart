import 'dart:convert';

import '../data/models/exif_info.dart';
import '../data/models/photo_metadata.dart';
import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';
import 'metadata_format.dart';

/// EXIF, MakerNote, OwnerName JSON, 파일명 분석 결과를 우선순위에 따라 병합한다.
///
/// 우선순위: MakerNote > OwnerName > EXIF > 파일명
class MetadataService {
  const MetadataService();
  PhotoMetadata merge({
    required ExifInfo exif,
    SeestarMetadata? makerNote,
    SeestarMetadata? ownerName,
    SeestarMetadata? filename,
  }) {
    AppLogger.metadata('MetadataService', '메타데이터 병합 시작');
    AppLogger.metadata(
      'MetadataService',
      '입력 makerNote=${makerNote?.objName ?? "null"}, '
          'ownerName=${ownerName?.objName ?? "null"}',
    );

    final seestar = makerNote;

    final capturedAt = _pick(
      [
        if (seestar?.date != null)
          ( _fromSeestarDate(seestar!.date), MetadataSource.makerNote),
        if (ownerName?.date != null && seestar?.date == null)
          (_fromSeestarDate(ownerName!.date), MetadataSource.ownerName),
        if (exif.date.isNotEmpty &&
            seestar?.date == null &&
            ownerName?.date == null)
          (exif.date, MetadataSource.exif),
        if (filename?.date != null &&
            seestar?.date == null &&
            ownerName?.date == null &&
            exif.date.isEmpty)
          (_fromSeestarDate(filename!.date), MetadataSource.filename),
      ],
    );

    final gps = _pickGps(
      seestar: seestar,
      ownerName: ownerName,
      exifLat: exif.lat,
      exifLng: exif.lng,
    );

    final equipment = _pick(
      [
        if (seestar?.creator != null)
          (seestar!.creator, MetadataSource.makerNote),
        if (ownerName?.creator != null && seestar?.creator == null)
          (ownerName!.creator, MetadataSource.ownerName),
        if (exif.equipment.isNotEmpty &&
            seestar?.creator == null &&
            ownerName?.creator == null)
          (exif.equipment, MetadataSource.exif),
      ],
    );

    final targetName = _pick(
      [
        if (seestar?.objName != null)
          (seestar!.objName, MetadataSource.makerNote),
        if (ownerName?.objName != null && seestar?.objName == null)
          (ownerName!.objName, MetadataSource.ownerName),
        if (filename?.objName != null &&
            seestar?.objName == null &&
            ownerName?.objName == null)
          (filename!.objName, MetadataSource.filename),
      ],
    );

    final stackNum = _pickInt(
      [
        if (seestar?.stackNum != null)
          (seestar!.stackNum, MetadataSource.makerNote),
        if (ownerName?.stackNum != null && seestar?.stackNum == null)
          (ownerName!.stackNum, MetadataSource.ownerName),
        if (filename?.stackNum != null &&
            seestar?.stackNum == null &&
            ownerName?.stackNum == null)
          (filename!.stackNum, MetadataSource.filename),
      ],
    );

    final singleExp = _pickExpSec(
      seestar: seestar,
      ownerName: ownerName,
      filename: filename,
    );

    final totalExp = _pickTotalExpSec(
      seestar: seestar,
      ownerName: ownerName,
      stackNum: stackNum.value,
      filename: filename,
      exifExposure: exif.exposure,
    );

    final filter = _pick(
      [
        if (filename?.filter != null)
          (filename!.filter, MetadataSource.filename),
      ],
    );

    final iso = _pick(
      [
        if (exif.iso.isNotEmpty) (exif.iso, MetadataSource.exif),
      ],
    );

    final fstop = _pick(
      [
        if (exif.fstop.isNotEmpty) (exif.fstop, MetadataSource.exif),
      ],
    );

    final focal = _pick(
      [
        if (exif.focal.isNotEmpty) (exif.focal, MetadataSource.exif),
      ],
    );

    final metadata = PhotoMetadata(
      targetName: targetName.value,
      targetNameSource: targetName.source,
      capturedAt: capturedAt.value,
      capturedAtSource: capturedAt.source,
      lat: gps.lat,
      lng: gps.lng,
      gpsSource: gps.source,
      equipment: equipment.value,
      equipmentSource: equipment.source,
      exposure: totalExp.value,
      exposureSource: totalExp.source,
      stackNum: stackNum.value,
      stackNumSource: stackNum.source,
      singleExpSec: singleExp.value,
      singleExpSecSource: singleExp.source,
      filter: filter.value,
      filterSource: filter.source,
      iso: iso.value,
      isoSource: iso.source,
      fstop: fstop.value,
      fstopSource: fstop.source,
      focal: focal.value,
      focalSource: focal.source,
      imageWidth: exif.imageWidth,
      imageHeight: exif.imageHeight,
      fileSize: exif.size.isNotEmpty ? exif.size : null,
      exifRaw: _buildExifRaw(exif),
      makerNoteJson: exif.makerNoteJson,
      ownerNameJson: exif.ownerNameJson,
      filenameRaw: _buildFilenameRaw(filename),
    );

    _logPhotoMetadataMapping(metadata);
    AppLogger.metadata('MetadataService', 'Metadata 병합 완료');
    AppLogger.metadata(
      'MetadataService',
      jsonEncode(metadata.toLogJson()),
    );

    return metadata;
  }

  /// Seestar 파싱 결과를 [ExifInfo]에 병합한다.
  ///
  /// 우선순위: MakerNote > OwnerName > 파일명 > 기존 EXIF
  ExifInfo mergeSeestarIntoExifInfo(
    ExifInfo exif, {
    SeestarMetadata? makerNote,
    SeestarMetadata? ownerName,
    SeestarMetadata? filename,
  }) {
    final seestar = makerNote;

    final targetName = _pick(
      [
        if (seestar?.objName != null)
          (seestar!.objName, MetadataSource.makerNote),
        if (ownerName?.objName != null && seestar?.objName == null)
          (ownerName!.objName, MetadataSource.ownerName),
        if (filename?.objName != null &&
            seestar?.objName == null &&
            ownerName?.objName == null)
          (filename!.objName, MetadataSource.filename),
      ],
    ).value;

    final capturedAt = _pick(
      [
        if (seestar?.date != null)
          (_fromSeestarDate(seestar!.date), MetadataSource.makerNote),
        if (ownerName?.date != null && seestar?.date == null)
          (_fromSeestarDate(ownerName!.date), MetadataSource.ownerName),
        if (filename?.date != null &&
            seestar?.date == null &&
            ownerName?.date == null)
          (_fromSeestarDate(filename!.date), MetadataSource.filename),
      ],
    ).value;

    final gps = _pickGps(
      seestar: seestar,
      ownerName: ownerName,
      exifLat: exif.lat,
      exifLng: exif.lng,
    );

    final stackNum = _pickInt(
      [
        if (seestar?.stackNum != null)
          (seestar!.stackNum, MetadataSource.makerNote),
        if (ownerName?.stackNum != null && seestar?.stackNum == null)
          (ownerName!.stackNum, MetadataSource.ownerName),
        if (filename?.stackNum != null &&
            seestar?.stackNum == null &&
            ownerName?.stackNum == null)
          (filename!.stackNum, MetadataSource.filename),
      ],
    ).value;

    final singleExp = _pickExpSec(
      seestar: seestar,
      ownerName: ownerName,
      filename: filename,
    ).value;

    final totalExp = _pickTotalExpSec(
      seestar: seestar,
      ownerName: ownerName,
      stackNum: stackNum,
      filename: filename,
      exifExposure: exif.exposure,
    ).value;

    return exif.copyWith(
      targetName: targetName ?? exif.targetName,
      date: capturedAt?.isNotEmpty == true ? capturedAt! : exif.date,
      lat: gps.lat ?? exif.lat,
      lng: gps.lng ?? exif.lng,
      stackNum: stackNum ?? exif.stackNum,
      singleExpSec: singleExp ?? exif.singleExpSec,
      exposure: totalExp?.isNotEmpty == true ? totalExp! : exif.exposure,
    );
  }

  /// [PhotoMetadata] 병합 결과를 [ExifInfo]에 반영한다.
  ExifInfo buildEnrichedExifInfo(ExifInfo exif, PhotoMetadata merged) {
    return exif.copyWith(
      targetName: merged.targetName ?? exif.targetName,
      date: merged.capturedAt?.isNotEmpty == true
          ? merged.capturedAt!
          : exif.date,
      equipment: merged.equipment?.isNotEmpty == true
          ? merged.equipment!
          : exif.equipment,
      lat: merged.lat ?? exif.lat,
      lng: merged.lng ?? exif.lng,
      stackNum: merged.stackNum ?? exif.stackNum,
      singleExpSec: merged.singleExpSec ?? exif.singleExpSec,
      exposure: merged.exposure?.isNotEmpty == true
          ? merged.exposure!
          : exif.exposure,
      filter: merged.filter ?? exif.filter,
      iso: merged.iso?.isNotEmpty == true ? merged.iso! : exif.iso,
      fstop: merged.fstop?.isNotEmpty == true ? merged.fstop! : exif.fstop,
      focal: merged.focal?.isNotEmpty == true ? merged.focal! : exif.focal,
    );
  }

  void _logPhotoMetadataMapping(PhotoMetadata metadata) {
    AppLogger.metadata(
      'MetadataService',
      'metadata.targetName = ${metadata.targetName ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.capturedAt = ${metadata.capturedAt ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.equipment = ${metadata.equipment ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.lat = ${metadata.lat?.toStringAsFixed(6) ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.lng = ${metadata.lng?.toStringAsFixed(6) ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.stackNum = ${metadata.stackNum ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.singleExpSec = ${metadata.singleExpSec ?? "-"}',
    );
    AppLogger.metadata(
      'MetadataService',
      'metadata.exposure = ${metadata.exposure ?? "-"}',
    );
  }

  Map<String, String> _buildExifRaw(ExifInfo exif) {
    return {
      if (exif.equipment.isNotEmpty) '장비명': exif.equipment,
      if (exif.date.isNotEmpty) 'DateTimeOriginal': exif.date,
      if (exif.lat != null) 'GPSLatitude': exif.lat!.toStringAsFixed(6),
      if (exif.lng != null) 'GPSLongitude': exif.lng!.toStringAsFixed(6),
      if (exif.exposure.isNotEmpty) 'ExposureTime': exif.exposure,
      if (exif.iso.isNotEmpty) 'ISO': exif.iso,
      if (exif.fstop.isNotEmpty) 'FNumber': exif.fstop,
      if (exif.focal.isNotEmpty) 'FocalLength': exif.focal,
      if (exif.filename.isNotEmpty) '파일명': exif.filename,
      if (exif.size.isNotEmpty) '파일크기': exif.size,
      if (exif.resolution.isNotEmpty) '해상도': exif.resolution,
      if (exif.imageWidth != null) '이미지너비': '${exif.imageWidth}',
      if (exif.imageHeight != null) '이미지높이': '${exif.imageHeight}',
    };
  }

  Map<String, String> _buildFilenameRaw(SeestarMetadata? filename) {
    return {
      if (filename?.objName != null) '대상명': filename!.objName!,
      if (filename?.stackNum != null) '스택수': '${filename!.stackNum}',
      if (filename?.expSec != null) '1장노출': '${filename!.expSec}s',
      if (filename?.filter != null) '필터': filename!.filter!,
      if (filename?.date != null) '날짜': filename!.date!,
    };
  }

  String? _fromSeestarDate(String? date) {
    if (date == null || date.isEmpty) return null;
    final dt = DateTime.tryParse(date.replaceFirst(' ', 'T'));
    return dt?.toIso8601String() ?? date;
  }

  _PickResult<String> _pick(List<(String?, MetadataSource)> options) {
    for (final option in options) {
      final value = option.$1;
      if (value != null && value.isNotEmpty) {
        return _PickResult(value, option.$2);
      }
    }
    return const _PickResult(null, null);
  }

  _PickResult<int> _pickInt(List<(int?, MetadataSource)> options) {
    for (final option in options) {
      final value = option.$1;
      if (value != null) {
        return _PickResult(value, option.$2);
      }
    }
    return const _PickResult(null, null);
  }

  _GpsResult _pickGps({
    SeestarMetadata? seestar,
    SeestarMetadata? ownerName,
    double? exifLat,
    double? exifLng,
  }) {
    if (seestar?.hasGps == true) {
      return _GpsResult(seestar!.lat, seestar.lng, MetadataSource.makerNote);
    }
    if (ownerName?.hasGps == true) {
      return _GpsResult(
        ownerName!.lat,
        ownerName.lng,
        MetadataSource.ownerName,
      );
    }
    if (exifLat != null && exifLng != null) {
      return _GpsResult(exifLat, exifLng, MetadataSource.exif);
    }
    return const _GpsResult(null, null, null);
  }

  _PickResult<String> _pickExpSec({
    SeestarMetadata? seestar,
    SeestarMetadata? ownerName,
    SeestarMetadata? filename,
  }) {
    if (seestar?.expSec != null) {
      return _PickResult(
        MetadataFormat.formatSeconds(seestar!.expSec!),
        MetadataSource.makerNote,
      );
    }
    if (ownerName?.expSec != null) {
      return _PickResult(
        MetadataFormat.formatSeconds(ownerName!.expSec!),
        MetadataSource.ownerName,
      );
    }
    if (filename?.expSec != null) {
      return _PickResult(
        MetadataFormat.formatSeconds(filename!.expSec!),
        MetadataSource.filename,
      );
    }
    return const _PickResult(null, null);
  }

  _PickResult<String> _pickTotalExpSec({
    SeestarMetadata? seestar,
    SeestarMetadata? ownerName,
    int? stackNum,
    SeestarMetadata? filename,
    required String exifExposure,
  }) {
    double? totSec = seestar?.calculatedTotExpSec;
    MetadataSource? source =
        seestar?.totExpSec != null || seestar?.expSec != null
            ? MetadataSource.makerNote
            : null;

    if (totSec == null && ownerName != null) {
      totSec = ownerName.calculatedTotExpSec;
      if (totSec != null) source = MetadataSource.ownerName;
    }

    if (totSec == null && stackNum != null && filename?.expSec != null) {
      totSec = stackNum * filename!.expSec!;
      source = MetadataSource.filename;
    }

    if (totSec != null) {
      return _PickResult(MetadataFormat.formatSeconds(totSec), source);
    }

    if (exifExposure.isNotEmpty) {
      return _PickResult(exifExposure, MetadataSource.exif);
    }

    return const _PickResult(null, null);
  }

  bool isTargetMatch(
    String? metadataTarget,
    String displayId,
    String objectName,
  ) {
    if (metadataTarget == null || metadataTarget.isEmpty) return true;
    final normalized = _normalize(metadataTarget);
    if (_normalize(displayId) == normalized) return true;
    if (_normalize(objectName) == normalized) return true;
    return false;
  }

  String _normalize(String input) =>
      input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

class _PickResult<T> {
  const _PickResult(this.value, this.source);
  final T? value;
  final MetadataSource? source;
}

class _GpsResult {
  const _GpsResult(this.lat, this.lng, this.source);
  final double? lat;
  final double? lng;
  final MetadataSource? source;
}
