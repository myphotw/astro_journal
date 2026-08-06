/// Seestar 사진에서 추출된 메타데이터.
///
/// OwnerName JSON 파싱 결과 또는 파일명 파싱 결과를 통합한다.
class SeestarMetadata {
  const SeestarMetadata({
    this.creator,
    this.objName,
    this.date,
    this.lat,
    this.lng,
    this.stackNum,
    this.expSec,
    this.totExpSec,
    this.imgType,
    this.eqmode,
    this.isWide,
    this.headerDate,
    this.bayerPat,
    this.isSolved,
    this.filter,
  });

  /// 제조사 (예: "ZWO").
  final String? creator;

  /// 촬영 대상명 (예: "M 27", "NGC 7000").
  final String? objName;

  /// 촬영 일시 문자열 (예: "2026-06-13 00:40:10").
  final String? date;

  /// 위도.
  final double? lat;

  /// 경도.
  final double? lng;

  /// 스택 수.
  final int? stackNum;

  /// 1장 노출시간 (초 단위, 예: 20.0).
  final double? expSec;

  /// 총 적분시간 (초 단위).
  final double? totExpSec;

  /// 이미지 타입 (예: "LIGHT").
  final String? imgType;

  /// 적도의 모드.
  final int? eqmode;

  /// 광각 여부.
  final bool? isWide;

  /// 헤더 날짜 문자열.
  final String? headerDate;

  /// 베이어 패턴 (예: "RGGB").
  final String? bayerPat;

  /// 플레이트 솔빙 여부.
  final bool? isSolved;

  /// 필터 (예: "LP", "LRGB", "None").
  /// OwnerName JSON에는 없고 파일명에서 추출한다.
  final String? filter;

  bool get hasGps => lat != null && lng != null;

  bool get hasCoreMetadata =>
      (objName != null && objName!.isNotEmpty) ||
      (date != null && date!.isNotEmpty) ||
      hasGps ||
      stackNum != null ||
      expSec != null ||
      totExpSec != null ||
      (creator != null && creator!.isNotEmpty);

  /// 촬영일시를 DateTime으로 변환한다.
  DateTime? get dateTime {
    if (date == null) return null;
    return DateTime.tryParse(date!.replaceFirst(' ', 'T'));
  }

  /// 총 적분시간을 계산한다.
  /// totExpSec가 있으면 그 값을 사용하고, 없으면 stackNum × expSec로 계산한다.
  double? get calculatedTotExpSec {
    if (totExpSec != null) return totExpSec;
    if (stackNum != null && expSec != null) return stackNum! * expSec!;
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'creator': creator,
      'objName': objName,
      'date': date,
      'lat': lat,
      'lng': lng,
      'stackNum': stackNum,
      'expSec': expSec,
      'totExpSec': totExpSec,
      'imgType': imgType,
      'eqmode': eqmode,
      'isWide': isWide,
      'headerDate': headerDate,
      'bayerPat': bayerPat,
      'isSolved': isSolved,
      'filter': filter,
    };
  }
}
