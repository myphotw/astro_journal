class ShootingTimeWindow {
  const ShootingTimeWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  bool get isValid => end.isAfter(start);

  bool contains(DateTime time) => !time.isBefore(start) && !time.isAfter(end);

  bool containsWindow(ShootingTimeWindow other) =>
      !other.start.isBefore(start) && !other.end.isAfter(end);

  bool overlaps(ShootingTimeWindow other) =>
      start.isBefore(other.end) && end.isAfter(other.start);

  ShootingTimeWindow? intersect(ShootingTimeWindow other) {
    final intersectionStart = start.isAfter(other.start) ? start : other.start;
    final intersectionEnd = end.isBefore(other.end) ? end : other.end;
    if (!intersectionEnd.isAfter(intersectionStart)) return null;
    return ShootingTimeWindow(start: intersectionStart, end: intersectionEnd);
  }
}
