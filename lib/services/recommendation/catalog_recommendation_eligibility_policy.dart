import '../../core/constants/catalog_type.dart';
import '../../data/models/catalog_object.dart';

enum RecommendationCandidateScope { all, representative, directTarget }

abstract final class CatalogRecommendationEligibilityPolicy {
  static bool allows(
    CatalogObject object,
    RecommendationCandidateScope scope,
  ) {
    return switch (scope) {
      RecommendationCandidateScope.all => true,
      RecommendationCandidateScope.representative =>
        object.isPrimaryCatalog &&
            (object.catalog == CatalogType.messier || object.isFeatured),
      RecommendationCandidateScope.directTarget => true,
    };
  }
}
