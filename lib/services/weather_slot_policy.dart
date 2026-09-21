import 'scheduler_engine.dart';

/// Shared time-bucket contract for weather used by recommendation and
/// scheduling. A partial slot advances to the next complete scheduler slot.
abstract final class WeatherSlotPolicy {
  static DateTime normalizeStart(DateTime time) {
    final slotMinutes = SchedulerEngine.slotDuration.inMinutes;
    final remainder = time.minute % slotMinutes;
    if (remainder == 0 &&
        time.second == 0 &&
        time.millisecond == 0 &&
        time.microsecond == 0) {
      return time;
    }
    final addMinutes = remainder == 0 ? slotMinutes : slotMinutes - remainder;
    return time
        .add(Duration(minutes: addMinutes))
        .copyWith(second: 0, millisecond: 0, microsecond: 0);
  }
}
