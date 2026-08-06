import 'equipment_recommendation.dart';

/// 단일 장비 Chip 표시 정보.
class CatalogEquipmentChipItem {
  const CatalogEquipmentChipItem({
    required this.label,
    required this.equipmentId,
    this.isVisual = false,
  });

  final String label;
  final String equipmentId;
  final bool isVisual;
}

/// 카탈로그·추천 카드에 표시할 장비 Chip 목록.
class CatalogEquipmentChips {
  const CatalogEquipmentChips({
    this.items = const [],
  });

  final List<CatalogEquipmentChipItem> items;

  bool get isEmpty => items.isEmpty;

  /// 하위 호환 — 촬영 장비 라벨만.
  List<String> get imagingLabels => items
      .where((item) => !item.isVisual)
      .map((item) => item.label)
      .toList();

  bool get showVisual => items.any((item) => item.isVisual);

  static CatalogEquipmentChips fromRecommendation(
    ObjectEquipmentRecommendation recommendation,
  ) {
    if (!recommendation.hasRegisteredEquipment) {
      return const CatalogEquipmentChips();
    }

    final items = <CatalogEquipmentChipItem>[];

    for (final imaging in recommendation.imaging) {
      final name = imaging.equipment.name.trim();
      if (name.isEmpty) continue;
      items.add(
        CatalogEquipmentChipItem(
          label: name,
          equipmentId: imaging.equipment.id,
        ),
      );
    }

    final visual = recommendation.visual.where((v) => v.isRecommended);
    if (visual.isNotEmpty) {
      final best = visual.first;
      items.add(
        CatalogEquipmentChipItem(
          label: '안시',
          equipmentId: best.equipment.id,
          isVisual: true,
        ),
      );
    }

    return CatalogEquipmentChips(items: items);
  }
}
