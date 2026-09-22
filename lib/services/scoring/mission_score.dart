import '../../data/models/catalog_object.dart';
import '../../data/models/observation_context.dart';

/// Neutral score component retained for recommendation score compatibility.
///
/// Capture history is user information and must not affect tonight's
/// recommendation score or scheduling priority.
class MissionScore {
  const MissionScore();

  double calculate({
    required CatalogObject object,
    required ObservationContext context,
  }) {
    return 100;
  }
}
