import '../../data/models/catalog_object.dart';
import '../../services/catalog_display_name_resolver.dart';
import 'catalog_metadata_format.dart';

/// 카탈로그 카드·검색·추천 등에서 공통으로 쓰는 표시 이름 포맷터.
abstract final class CatalogObjectDisplayFormatter {
  /// 1줄: 항상 카탈로그명 (M42, Sh2-196 등).
  static String catalogTitle(CatalogObject object) => object.displayName;

  /// 2줄: Display Name·Object Type 규칙에 따른 부제.
  /// 표시할 내용이 없으면 null.
  static String? subtitle(CatalogObject object) {
    final objectType = _validLabel(object.displayType);
    final uiName = CatalogDisplayNameResolver.uiDisplayName(object);

    if (uiName != null && objectType != null) {
      if (labelsMatch(uiName, objectType)) {
        return uiName;
      }
      return '$uiName($objectType)';
    }

    if (uiName != null) {
      return uiName;
    }

    return objectType;
  }

  static String subtitleText(CatalogObject object) => subtitle(object) ?? '';

  /// 검색·리스트 타일용 부제 (별자리 포함).
  static String listSubtitle(
    CatalogObject object, {
    bool includeConstellation = true,
  }) {
    final parts = <String>[];
    final main = subtitleText(object);
    if (main.isNotEmpty) {
      parts.add(main);
    }

    if (includeConstellation) {
      final constellation = object.displayConstellation.trim();
      if (constellation.isNotEmpty && constellation != '-') {
        parts.add(constellation);
      }
    }

    return parts.join(' · ');
  }

  static bool labelsMatch(String a, String b) {
    return _normalizeLabel(a) == _normalizeLabel(b);
  }

  static String? _validLabel(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return null;
    }
    return trimmed;
  }

  static String _normalizeLabel(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  /// 광년 거리 표시. [CatalogMetadataFormat.formatDistanceLy] 위임.
  static String? formatDistanceLy(num? distanceLy) =>
      CatalogMetadataFormat.formatDistanceLy(distanceLy);

  /// 각크기 표시. [CatalogMetadataFormat.formatAngularSize] 위임.
  static String formatAngularSize(String raw) =>
      CatalogMetadataFormat.formatAngularSize(raw);
}
