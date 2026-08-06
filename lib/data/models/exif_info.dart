class ExifInfo {
  const ExifInfo({
    required this.filename,
    required this.size,
    required this.date,
    required this.equipment,
    required this.focal,
    required this.fstop,
    required this.exposure,
    required this.iso,
    required this.resolution,
    this.originalFilename,
    this.targetName,
    this.lat,
    this.lng,
    this.locationName,
    this.address,
    this.stackNum,
    this.singleExpSec,
    this.filter,
    this.imageWidth,
    this.imageHeight,
    this.ownerNameJson,
    this.makerNoteJson,
    this.ra,
    this.dec,
  });

  /// 갤러리 원본 파일명 (내부 UUID 경로와 별도).
  final String filename;

  /// [filename]과 동일 — DB/표시용 명시 필드.
  final String? originalFilename;

  final String size;

  /// 촬영일시 (ISO 8601, DateTimeOriginal 또는 Seestar date).
  final String date;

  /// 촬영 대상명 (MakerNote/OwnerName/파일명에서 추출).
  final String? targetName;

  /// 장비명 (Make + Model 또는 Seestar creator).
  final String equipment;

  /// 초점거리 (예: "280 mm").
  final String focal;

  /// 조리개값 (예: "f/4.0").
  final String fstop;

  /// 총 적분시간 (Seestar tot_exp_sec 또는 EXIF ExposureTime).
  final String exposure;

  /// ISO (예: "ISO 1600").
  final String iso;

  /// 해상도 문자열 (예: "4024 × 3024").
  final String resolution;

  final double? lat;
  final double? lng;

  /// Geocoding으로 조회한 촬영지명.
  final String? locationName;

  /// Geocoding으로 조회한 전체 주소.
  final String? address;

  /// 스택 수 (MakerNote 또는 파일명에서 추출).
  final int? stackNum;

  /// 1장 노출시간 문자열 (예: "20초").
  final String? singleExpSec;

  /// 필터 (예: "LP", "LRGB", "None").
  final String? filter;

  /// 이미지 너비 (픽셀).
  final int? imageWidth;

  /// 이미지 높이 (픽셀).
  final int? imageHeight;

  /// EXIF OwnerName / CameraOwnerName 태그 원본 JSON 문자열 (Seestar 전용).
  final String? ownerNameJson;

  /// EXIF MakerNote 태그 원본 JSON 문자열 (Seestar 전용).
  final String? makerNoteJson;

  /// EXIF/XMP에 이미 기록된 적경 (degrees). 대부분의 촬영 장비는 기록하지
  /// 않으며, 존재하는 경우 Plate Solve를 생략하는 판단 기준으로 사용한다.
  final double? ra;

  /// EXIF/XMP에 이미 기록된 적위 (degrees).
  final double? dec;

  /// EXIF 추출 전 placeholder — UI를 먼저 열고 비동기로 채울 때 사용.
  factory ExifInfo.placeholder({required String filename}) {
    return ExifInfo(
      filename: filename,
      originalFilename: filename,
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

  /// Placeholder 여부 (progressive EXIF 게이트).
  bool get isPlaceholder =>
      date.isEmpty &&
      equipment.isEmpty &&
      focal.isEmpty &&
      fstop.isEmpty &&
      exposure.isEmpty &&
      iso.isEmpty &&
      resolution.isEmpty &&
      size.isEmpty &&
      targetName == null &&
      lat == null &&
      lng == null &&
      stackNum == null;

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'originalFilename': originalFilename ?? filename,
      'size': size,
      'date': date,
      'targetName': targetName,
      'equipment': equipment,
      'focal': focal,
      'fstop': fstop,
      'exposure': exposure,
      'iso': iso,
      'resolution': resolution,
      'lat': lat,
      'lng': lng,
      'locationName': locationName,
      'address': address,
      'stackNum': stackNum,
      'singleExpSec': singleExpSec,
      'filter': filter,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'ownerNameJson': ownerNameJson,
      'makerNoteJson': makerNoteJson,
      'ra': ra,
      'dec': dec,
    };
  }

  factory ExifInfo.fromJson(Map<String, dynamic> json) {
    final filename = json['filename'] as String? ?? '';
    return ExifInfo(
      filename: filename,
      originalFilename:
          json['originalFilename'] as String? ?? (filename.isNotEmpty ? filename : null),
      size: json['size'] as String? ?? '',
      date: json['date'] as String? ?? '',
      targetName: json['targetName'] as String?,
      equipment: json['equipment'] as String? ?? '',
      focal: json['focal'] as String? ?? '',
      fstop: json['fstop'] as String? ?? '',
      exposure: json['exposure'] as String? ?? '',
      iso: json['iso'] as String? ?? '',
      resolution: json['resolution'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      locationName: json['locationName'] as String?,
      address: json['address'] as String?,
      stackNum: (json['stackNum'] as num?)?.toInt(),
      singleExpSec: json['singleExpSec'] as String?,
      filter: json['filter'] as String?,
      imageWidth: (json['imageWidth'] as num?)?.toInt(),
      imageHeight: (json['imageHeight'] as num?)?.toInt(),
      ownerNameJson: json['ownerNameJson'] as String?,
      makerNoteJson: json['makerNoteJson'] as String?,
      ra: (json['ra'] as num?)?.toDouble(),
      dec: (json['dec'] as num?)?.toDouble(),
    );
  }

  ExifInfo copyWith({
    String? filename,
    String? originalFilename,
    String? size,
    String? date,
    String? targetName,
    String? equipment,
    String? focal,
    String? fstop,
    String? exposure,
    String? iso,
    String? resolution,
    double? lat,
    double? lng,
    String? locationName,
    String? address,
    int? stackNum,
    String? singleExpSec,
    String? filter,
    int? imageWidth,
    int? imageHeight,
    String? ownerNameJson,
    String? makerNoteJson,
    double? ra,
    double? dec,
  }) {
    return ExifInfo(
      filename: filename ?? this.filename,
      originalFilename: originalFilename ?? this.originalFilename,
      size: size ?? this.size,
      date: date ?? this.date,
      targetName: targetName ?? this.targetName,
      equipment: equipment ?? this.equipment,
      focal: focal ?? this.focal,
      fstop: fstop ?? this.fstop,
      exposure: exposure ?? this.exposure,
      iso: iso ?? this.iso,
      resolution: resolution ?? this.resolution,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      locationName: locationName ?? this.locationName,
      address: address ?? this.address,
      stackNum: stackNum ?? this.stackNum,
      singleExpSec: singleExpSec ?? this.singleExpSec,
      filter: filter ?? this.filter,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      ownerNameJson: ownerNameJson ?? this.ownerNameJson,
      makerNoteJson: makerNoteJson ?? this.makerNoteJson,
      ra: ra ?? this.ra,
      dec: dec ?? this.dec,
    );
  }
}
