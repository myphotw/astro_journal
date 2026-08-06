import 'equipment.dart';
import 'recommendation_result.dart';

/// 추천 장비 탭 Carousel 한 페이지 데이터.
class EquipmentTonightGroup {
  const EquipmentTonightGroup({
    required this.equipment,
    required this.targets,
    required this.starCount,
    required this.isVisual,
  });

  final Equipment equipment;
  final List<RecommendationResult> targets;

  /// 매칭 대상 중 최고 추천 별점 (1–5).
  final int starCount;

  /// true이면 「오늘 안시 추천」, false이면 「오늘 추천 대상」.
  final bool isVisual;

  String get sectionTitle => isVisual ? '오늘 안시 추천' : '오늘 추천 대상';
}
