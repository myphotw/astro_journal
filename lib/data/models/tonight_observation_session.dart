/// Tonight's observation planning window (sunset twilight through sunrise).
class TonightObservationSession {
  const TonightObservationSession({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;

  Duration get observableDuration => end.difference(start);

  factory TonightObservationSession.fromTimes({
    required DateTime start,
    required DateTime end,
  }) {
    return TonightObservationSession(start: start, end: end);
  }
}
