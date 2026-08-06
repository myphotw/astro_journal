/// 촬영 대상이 어떤 방식으로 식별되었는지를 나타낸다.
///
/// [ShootingRecord.detectMethod]에 저장되며, Gallery 등에서 자동 인식
/// 결과의 출처를 사용자에게 알려주는 용도로 사용된다.
enum DetectMethod {
  /// EXIF(MakerNote/CameraOwnerName 등)에 기록된 대상명·좌표로 식별.
  exif,

  /// 파일명 패턴 분석으로 식별 (Seestar 파일명 규칙 등).
  filename,

  /// Plate Solve로 얻은 RA/DEC 기준 Catalog 검색으로 식별.
  plateSolve,

  /// 사용자가 직접 검색해서 선택.
  manual;

  String get value {
    switch (this) {
      case DetectMethod.exif:
        return 'EXIF';
      case DetectMethod.filename:
        return 'FILENAME';
      case DetectMethod.plateSolve:
        return 'PLATE_SOLVE';
      case DetectMethod.manual:
        return 'MANUAL';
    }
  }

  static DetectMethod? fromValue(String? value) {
    switch (value) {
      case 'EXIF':
        return DetectMethod.exif;
      case 'FILENAME':
        return DetectMethod.filename;
      case 'PLATE_SOLVE':
        return DetectMethod.plateSolve;
      case 'MANUAL':
        return DetectMethod.manual;
      default:
        return null;
    }
  }

  /// Gallery/상세 화면 표시용 라벨.
  String get label {
    switch (this) {
      case DetectMethod.exif:
        return 'EXIF 자동 인식';
      case DetectMethod.filename:
        return '파일명 자동 인식';
      case DetectMethod.plateSolve:
        return 'Plate Solve 자동 인식';
      case DetectMethod.manual:
        return '수동 등록';
    }
  }
}
