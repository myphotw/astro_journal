import 'catalog_type.dart';

/// Catalog tie-break order for recommendation sorting (lower = higher priority).
abstract final class RecommendationCatalogPriority {
  static const _order = [
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
    CatalogType.caldwell,
    CatalogType.rcw,
    CatalogType.vdb,
  ];

  static int rank(CatalogType catalog) {
    final index = _order.indexOf(catalog);
    return index >= 0 ? index : _order.length;
  }
}
