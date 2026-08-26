import 'package:flutter/foundation.dart';

import 'performance_probe.dart';

enum ObservationContextChange {
  equipment,
  observationSite,
  activeSite,
  trackingMode,
  horizon,
}

typedef ObservationContextReload =
    Future<void> Function(ObservationContextChange change);

/// Shared mutation signal for every input that can change observation results.
class ObservationContextInvalidator extends ChangeNotifier {
  ObservationContextReload? _reload;
  Future<void> _pending = Future.value();
  int _revision = 0;
  ObservationContextChange? _latestChange;

  int get revision => _revision;
  ObservationContextChange? get latestChange => _latestChange;

  void bind(ObservationContextReload reload) {
    _reload = reload;
  }

  void unbind() => _reload = null;

  Future<void> invalidate(ObservationContextChange change) {
    _revision += 1;
    _latestChange = change;
    final revision = _revision;
    PerformanceProbe.event(
      'observation_context.invalidate',
      state: 'revision=$revision change=${change.name}',
    );
    notifyListeners();

    final reload = _reload;
    if (reload == null) return Future.value();

    final current = _pending.then(
      (_) => PerformanceProbe.measureAsync(
        'observation_context.reload',
        () => reload(change),
        state: 'revision=$revision change=${change.name}',
      ),
      onError: (Object _, StackTrace _) => PerformanceProbe.measureAsync(
        'observation_context.reload',
        () => reload(change),
        state: 'revision=$revision change=${change.name}',
      ),
    );
    _pending = current.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return current;
  }
}
