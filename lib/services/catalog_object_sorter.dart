import '../core/constants/catalog_sort_order.dart';
import '../core/constants/catalog_type.dart';
import '../data/models/catalog_object.dart';
import 'catalog_display_name_resolver.dart';

/// 카탈로그 목록 정렬.
abstract final class CatalogObjectSorter {
  static final RegExp _naturalChunkPattern = RegExp(r'(\d+)|(\D+)');

  static List<CatalogObject> sort(
    Iterable<CatalogObject> objects,
    CatalogSortOrder order,
  ) {
    final sorted = objects.toList();
    sorted.sort((a, b) => compare(a, b, order));
    return sorted;
  }

  static int compare(
    CatalogObject a,
    CatalogObject b,
    CatalogSortOrder order,
  ) {
    return switch (order) {
      CatalogSortOrder.defaultOrder => _compareDefault(a, b),
      CatalogSortOrder.nameAsc => _compareName(a, b),
      CatalogSortOrder.catalogNumber => _compareCatalogNumber(a, b),
      CatalogSortOrder.constellation => _compareConstellation(a, b),
      CatalogSortOrder.objectType => _compareObjectType(a, b),
    };
  }

  /// Messier 번호순, 그 외는 대표 천체·우선순위·이름순.
  static int _compareDefault(CatalogObject a, CatalogObject b) {
    final catalogCompare = _compareCatalogKind(a, b);
    if (catalogCompare != 0) {
      return catalogCompare;
    }

    if (a.catalog == CatalogType.messier && b.catalog == CatalogType.messier) {
      final numberCompare = a.number.compareTo(b.number);
      if (numberCompare != 0) {
        return numberCompare;
      }
    }

    final featuredCompare =
        (b.isFeatured ? 1 : 0).compareTo(a.isFeatured ? 1 : 0);
    if (featuredCompare != 0) {
      return featuredCompare;
    }

    final priorityCompare = a.displayPriority.compareTo(b.displayPriority);
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    return compareNatural(a.name, b.name);
  }

  static int _compareName(CatalogObject a, CatalogObject b) {
    final nameCompare = compareNatural(_sortableName(a), _sortableName(b));
    if (nameCompare != 0) {
      return nameCompare;
    }
    return _compareCatalogNumber(a, b);
  }

  static int _compareCatalogNumber(CatalogObject a, CatalogObject b) {
    final catalogCompare = _compareCatalogKind(a, b);
    if (catalogCompare != 0) {
      return catalogCompare;
    }

    final numberCompare = a.number.compareTo(b.number);
    if (numberCompare != 0) {
      return numberCompare;
    }

    final suffixA = a.suffix ?? '';
    final suffixB = b.suffix ?? '';
    return suffixA.compareTo(suffixB);
  }

  static int _compareConstellation(CatalogObject a, CatalogObject b) {
    final constellationCompare =
        a.displayConstellation.compareTo(b.displayConstellation);
    if (constellationCompare != 0) {
      return constellationCompare;
    }
    return _compareDefault(a, b);
  }

  static int _compareObjectType(CatalogObject a, CatalogObject b) {
    final typeCompare = a.displayType.compareTo(b.displayType);
    if (typeCompare != 0) {
      return typeCompare;
    }
    return _compareDefault(a, b);
  }

  static int _compareCatalogKind(CatalogObject a, CatalogObject b) {
    return a.catalog.mergePriority.compareTo(b.catalog.mergePriority);
  }

  static String _sortableName(CatalogObject object) {
    final resolved = CatalogDisplayNameResolver.resolve(object);
    if (resolved != null && resolved.trim().isNotEmpty) {
      return resolved.trim();
    }
    // 한글 통칭이 없으면 카탈로그 표기(M1, NGC 101…)로 정렬.
    return object.displayName;
  }

  /// 숫자 구간은 정수로 비교해 M1 < M2 < M10 < M101 순이 되게 한다.
  static int compareNatural(String a, String b) {
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    if (left == right) return 0;

    final leftChunks = _naturalChunkPattern.allMatches(left).toList();
    final rightChunks = _naturalChunkPattern.allMatches(right).toList();
    final count = leftChunks.length < rightChunks.length
        ? leftChunks.length
        : rightChunks.length;

    for (var i = 0; i < count; i++) {
      final leftChunk = leftChunks[i].group(0)!;
      final rightChunk = rightChunks[i].group(0)!;
      final leftNumber = int.tryParse(leftChunk);
      final rightNumber = int.tryParse(rightChunk);

      if (leftNumber != null && rightNumber != null) {
        final numberCompare = leftNumber.compareTo(rightNumber);
        if (numberCompare != 0) return numberCompare;
        continue;
      }

      final textCompare = leftChunk.compareTo(rightChunk);
      if (textCompare != 0) return textCompare;
    }

    return leftChunks.length.compareTo(rightChunks.length);
  }
}
