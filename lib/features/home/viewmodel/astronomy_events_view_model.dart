import 'package:flutter/foundation.dart';

import '../../../data/models/astronomy_event.dart';
import '../../../data/repositories/astronomy_event_repository.dart';

class AstronomyEventsViewModel extends ChangeNotifier {
  AstronomyEventsViewModel(this._repository);

  final AstronomyEventRepository _repository;

  List<AstronomyEvent> _events = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isDisposed = false;
  String? _errorMessage;
  Future<void>? _activeLoad;

  List<AstronomyEvent> get events => _events;
  List<AstronomyEvent> get homeEvents =>
      _events.take(3).toList(growable: false);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool force = false}) {
    final activeLoad = _activeLoad;
    if (activeLoad != null) return activeLoad;
    if (_hasLoaded && !force) return Future<void>.value();

    _isLoading = true;
    _errorMessage = null;
    _notifyIfMounted();

    final load = _performLoad();
    _activeLoad = load;
    return load;
  }

  Future<void> refresh() => load(force: true);

  Future<void> _performLoad() async {
    try {
      _events = await _repository.getUpcomingEvents();
      _errorMessage = null;
    } catch (_) {
      _errorMessage = '천문 이벤트를 불러오지 못했습니다.';
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      _activeLoad = null;
      _notifyIfMounted();
    }
  }

  void _notifyIfMounted() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
