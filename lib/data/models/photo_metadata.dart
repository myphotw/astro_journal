/// 메타데이터 출처.
library;

enum MetadataSource {
  makerNote('MakerNote'),

  ownerName('OwnerName'),

  exif('EXIF'),

  filename('FileName'),

  user('수동입력');



  const MetadataSource(this.label);

  final String label;



  /// UI 배지용 짧은 라벨.

  String get badgeLabel {

    switch (this) {

      case MetadataSource.makerNote:

        return 'MakerNote';

      case MetadataSource.ownerName:

        return 'OwnerName';

      case MetadataSource.exif:

        return 'EXIF';

      case MetadataSource.filename:

        return 'FileName';

      case MetadataSource.user:

        return '수동';

    }

  }

}



/// 사진에서 추출된 통합 메타데이터.

///

/// 우선순위: MakerNote > OwnerName > EXIF > 파일명

class PhotoMetadata {

  const PhotoMetadata({

    this.targetName,

    this.targetNameSource,

    this.capturedAt,

    this.capturedAtSource,

    this.lat,

    this.lng,

    this.gpsSource,

    this.equipment,

    this.equipmentSource,

    this.exposure,

    this.exposureSource,

    this.stackNum,

    this.stackNumSource,

    this.singleExpSec,

    this.singleExpSecSource,

    this.filter,

    this.filterSource,

    this.iso,

    this.isoSource,

    this.fstop,

    this.fstopSource,

    this.focal,

    this.focalSource,

    this.imageWidth,

    this.imageHeight,

    this.fileSize,

    this.exifRaw = const {},

    this.makerNoteJson,

    this.ownerNameJson,

    this.filenameRaw = const {},

  });



  final String? targetName;

  final MetadataSource? targetNameSource;



  final String? capturedAt;

  final MetadataSource? capturedAtSource;



  final double? lat;

  final double? lng;

  final MetadataSource? gpsSource;



  final String? equipment;

  final MetadataSource? equipmentSource;



  final String? exposure;

  final MetadataSource? exposureSource;



  final int? stackNum;

  final MetadataSource? stackNumSource;



  final String? singleExpSec;

  final MetadataSource? singleExpSecSource;



  final String? filter;

  final MetadataSource? filterSource;



  final String? iso;

  final MetadataSource? isoSource;



  final String? fstop;

  final MetadataSource? fstopSource;



  final String? focal;

  final MetadataSource? focalSource;



  final int? imageWidth;

  final int? imageHeight;

  final String? fileSize;



  final Map<String, String> exifRaw;

  final String? makerNoteJson;

  final String? ownerNameJson;

  final Map<String, String> filenameRaw;



  bool get hasGps => lat != null && lng != null;



  bool get hasAnyMetadata =>

      targetName != null ||

      capturedAt != null ||

      equipment != null ||

      hasGps ||

      stackNum != null ||

      singleExpSec != null ||

      exposure != null ||

      filter != null ||

      iso != null ||

      fstop != null ||

      focal != null;



  (int recognized, int total) recognitionScore() {

    const total = 10;

    var count = 0;

    if (targetName != null && targetName!.isNotEmpty) count++;

    if (capturedAt != null && capturedAt!.isNotEmpty) count++;

    if (equipment != null && equipment!.isNotEmpty) count++;

    if (hasGps) count++;

    if (stackNum != null) count++;

    if (singleExpSec != null && singleExpSec!.isNotEmpty) count++;

    if (exposure != null && exposure!.isNotEmpty) count++;

    if (iso != null && iso!.isNotEmpty) count++;

    if (fstop != null && fstop!.isNotEmpty) count++;

    if (focal != null && focal!.isNotEmpty) count++;

    return (count, total);

  }



  /// Debug 로그용 JSON 맵.
  Map<String, dynamic> toLogJson() {
    return {
      'targetName': targetName,
      'targetNameSource': targetNameSource?.badgeLabel,
      'capturedAt': capturedAt,
      'capturedAtSource': capturedAtSource?.badgeLabel,
      'equipment': equipment,
      'equipmentSource': equipmentSource?.badgeLabel,
      'lat': lat,
      'lng': lng,
      'gpsSource': gpsSource?.badgeLabel,
      'stackNum': stackNum,
      'stackNumSource': stackNumSource?.badgeLabel,
      'singleExpSec': singleExpSec,
      'singleExpSecSource': singleExpSecSource?.badgeLabel,
      'exposure': exposure,
      'exposureSource': exposureSource?.badgeLabel,
      'filter': filter,
      'iso': iso,
      'fstop': fstop,
      'focal': focal,
    };
  }

  Map<String, String> sourceLogMap() {

    return {

      'Target': _sourceLabel(targetName, targetNameSource),

      'Date': _sourceLabel(capturedAt, capturedAtSource),

      'Equipment': _sourceLabel(equipment, equipmentSource),

      'GPS': hasGps ? (gpsSource?.badgeLabel ?? '?') : '-',

      'StackNum': _sourceLabel(stackNum?.toString(), stackNumSource),

      'ExpSec': _sourceLabel(singleExpSec, singleExpSecSource),

      'TotExpSec': _sourceLabel(exposure, exposureSource),

      'Filter': _sourceLabel(filter, filterSource),

      'ISO': _sourceLabel(iso, isoSource),

      'FStop': _sourceLabel(fstop, fstopSource),

      'Focal': _sourceLabel(focal, focalSource),

    };

  }



  String _sourceLabel(Object? value, MetadataSource? source) {

    if (value == null) return '-';

    if (value is String && value.isEmpty) return '-';

    return source?.badgeLabel ?? '?';

  }

}


