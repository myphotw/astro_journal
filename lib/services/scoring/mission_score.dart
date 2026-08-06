import '../../data/models/catalog_object.dart';
import '../../data/models/observation_context.dart';

/// Rewards uncaptured targets and recent shooting gaps.
class MissionScore {
  const MissionScore();

  double calculate({
    required CatalogObject object,
    required ObservationContext context,
  }) {
    if (!object.captured) {
      return 100;
    }

    final records = context.shootingRecords
        .where((record) => record.celestialObjectId == object.id)
        .toList();
    if (records.isEmpty) {
      return 60;
    }

    records.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final daysSince =
        context.currentTime.difference(records.first.capturedAt).inDays;
    if (daysSince >= 365) return 80;
    if (daysSince >= 180) return 50;
    return 20;
  }
}
