/// 카탈로그 목록 정렬 방식.
enum CatalogSortOrder {
  /// DB 기본: 카탈로그 종류 → 대표 천체 → 우선순위 → 이름.
  defaultOrder,

  /// 표시 이름 가나다순.
  nameAsc,

  /// 카탈로그 종류 → 번호순.
  catalogNumber,

  /// 별자리 → 기본 정렬.
  constellation,

  /// 천체 유형 → 기본 정렬.
  objectType,
}

extension CatalogSortOrderLabel on CatalogSortOrder {
  String get label {
    switch (this) {
      case CatalogSortOrder.defaultOrder:
        return '기본';
      case CatalogSortOrder.nameAsc:
        return '이름순';
      case CatalogSortOrder.catalogNumber:
        return '번호순';
      case CatalogSortOrder.constellation:
        return '별자리순';
      case CatalogSortOrder.objectType:
        return '유형순';
    }
  }
}
