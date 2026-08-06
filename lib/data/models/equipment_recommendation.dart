import 'equipment.dart';

import 'eyepiece.dart';



/// 천체·조건에 대한 장비 추천 결과 묶음.

class ObjectEquipmentRecommendation {

  const ObjectEquipmentRecommendation({

    required this.imaging,

    required this.visual,

    this.hasRegisteredEquipment = true,

  });



  final List<ImagingEquipmentRecommendation> imaging;

  final List<VisualEquipmentRecommendation> visual;

  final bool hasRegisteredEquipment;



  static const empty = ObjectEquipmentRecommendation(

    imaging: [],

    visual: [],

    hasRegisteredEquipment: false,

  );

}



class ImagingEquipmentRecommendation {

  const ImagingEquipmentRecommendation({

    required this.equipment,

    required this.score,

    required this.starCount,

    required this.reason,

    required this.screenFillPercent,

    this.screenFillNote,

    this.rank = 0,

  });



  final Equipment equipment;

  final double score;

  final int starCount;

  final String reason;

  final int screenFillPercent;

  final String? screenFillNote;

  final int rank;

}



class VisualEquipmentRecommendation {

  const VisualEquipmentRecommendation({

    required this.equipment,

    this.eyepiece,

    required this.score,

    required this.starCount,

    required this.reason,

    required this.isRecommended,

    required this.screenFillPercent,

    this.screenFillNote,

    this.isFeasibleToday = true,

  });



  final Equipment equipment;

  final Eyepiece? eyepiece;

  final double score;

  final int starCount;

  final String reason;

  final bool isRecommended;

  final int screenFillPercent;

  final String? screenFillNote;



  /// 오늘 조건 기준 안시 가능 여부.

  final bool isFeasibleToday;



  /// 아이피스 초점거리 (mm) 표시. 이름과 무관하게 항상 mm를 노출한다.

  String get eyepieceFocalLabel {

    if (eyepiece == null) return '';

    final mm = eyepiece!.focalLengthMm;

    final text = mm == mm.roundToDouble()

        ? mm.toStringAsFixed(0)

        : mm.toStringAsFixed(1);

    return '${text}mm';

  }



  String get eyepieceDisplayName {

    if (eyepiece == null) return '';

    final name = eyepiece!.name.trim();

    if (name.isNotEmpty) return name;

    return eyepieceFocalLabel;

  }



  String get eyepieceLabel =>

      eyepieceFocalLabel.isNotEmpty ? '$eyepieceFocalLabel 아이피스' : '';



  VisualEquipmentRecommendation copyWith({

    Equipment? equipment,

    Eyepiece? eyepiece,

    double? score,

    int? starCount,

    String? reason,

    bool? isRecommended,

    int? screenFillPercent,

    String? screenFillNote,

    bool? isFeasibleToday,

  }) {

    return VisualEquipmentRecommendation(

      equipment: equipment ?? this.equipment,

      eyepiece: eyepiece ?? this.eyepiece,

      score: score ?? this.score,

      starCount: starCount ?? this.starCount,

      reason: reason ?? this.reason,

      isRecommended: isRecommended ?? this.isRecommended,

      screenFillPercent: screenFillPercent ?? this.screenFillPercent,

      screenFillNote: screenFillNote ?? this.screenFillNote,

      isFeasibleToday: isFeasibleToday ?? this.isFeasibleToday,

    );

  }

}



/// 추천대상 상세용 — 오늘 최적 장비 1건씩.

class TodayEquipmentRecommendation {

  const TodayEquipmentRecommendation({

    this.imaging,

    this.visual = const [],

    this.hasRegisteredEquipment = true,

  });



  final ImagingEquipmentRecommendation? imaging;

  final List<VisualEquipmentRecommendation> visual;

  final bool hasRegisteredEquipment;



  static const empty = TodayEquipmentRecommendation(

    hasRegisteredEquipment: false,

  );

}

