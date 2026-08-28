import '../models/astronomy_event.dart';

abstract interface class AstronomyEventRepository {
  Future<List<AstronomyEvent>> getUpcomingEvents({
    DateTime? from,
    DateTime? to,
  });
}
