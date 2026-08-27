import 'package:flutter/foundation.dart';

import 'performance_probe.dart';

enum ObservationContextChange {
  equipment,
  observationSite,
  activeSite,
  trackingMode,
  horizon,
  recommendationSettings,
}

typedef ObservationContextReload =
    Future<void> Function(ObservationContextChange change, int revision);

/// Shared mutation signal for every input that can change observation results.
class ObservationContextInvalidator extends ChangeNotifier {
  ObservationContextReload? _reload;
  Object? _bindingToken;
  Future<void> _pending = Future.value();
  int _revision = 0;
  ObservationContextChange? _latestChange;

  int get revision => _revision;
  ObservationContextChange? get latestChange => _latestChange;

  Object bind(ObservationContextReload reload) {
    final token = Object();
    _reload = reload;
    _bindingToken = token;
    return token;
  }

  void unbind([Object? token]) {
    if (token != null && !identical(token, _bindingToken)) return;
    _reload = null;
    _bindingToken = null;
  }

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
        () => reload(change, revision),
        state: 'revision=$revision change=${change.name}',
      ),
      onError: (Object _, StackTrace _) => PerformanceProbe.measureAsync(
        'observation_context.reload',
        () => reload(change, revision),
        state: 'revision=$revision change=${change.name}',
      ),
    );
    _pending = current.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return current;
  }
}
