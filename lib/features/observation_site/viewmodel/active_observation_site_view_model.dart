import 'package:flutter/foundation.dart';

import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../models/active_observation_site.dart';

class ActiveObservationSiteViewModel extends ChangeNotifier {
  ActiveObservationSiteViewModel(this._repository);

  final ObservationSiteRepository _repository;
  ActiveObservationSite _active = const ActiveObservationSite.currentLocation();
  List<ObservationSite> _sites = const [];
  bool _loaded = false;
  bool _loading = false;

  ActiveObservationSite get active => _active;
  List<ObservationSite> get sites => List.unmodifiable(_sites);
  bool get isLoading => _loading;
  bool get isLoaded => _loaded;

  Future<void> load({bool force = false}) async {
    if (_loading || (_loaded && !force)) return;
    _loading = true;
    notifyListeners();
    try {
      final sites = await _repository.list();
      _sites = _sortSites(sites);
      final selectedId = _active.selectedSiteId;
      if (selectedId != null) {
        final selected = _findSite(selectedId);
        _active = selected == null
            ? const ActiveObservationSite.currentLocation()
            : ActiveObservationSite.saved(
                selected,
                temporaryTrackingOverride: _active.temporaryTrackingOverride,
                temporaryEquipmentOverrideId:
                    _active.temporaryEquipmentOverrideId,
              );
      }
      _loaded = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectCurrentLocation() async {
    _active = const ActiveObservationSite.currentLocation();
    notifyListeners();
  }

  Future<void> selectSavedSite(ObservationSite site) async {
    final usedAt = DateTime.now();
    await _repository.markLastUsed(site.id, usedAt);
    final selected = site.copyWith(lastUsedAt: usedAt);
    _replaceSite(selected);
    _active = ActiveObservationSite.saved(selected);
    notifyListeners();
  }

  void updateCurrentLocation({
    required double latitude,
    required double longitude,
  }) {
    if (!_active.isCurrentLocation) return;
    _active = _active.copyWithCurrentLocation(
      latitude: latitude,
      longitude: longitude,
    );
    notifyListeners();
  }

  void updateSavedSite(ObservationSite site, {bool clearOverrides = false}) {
    _replaceSite(site);
    if (_active.selectedSiteId == site.id) {
      _active = ActiveObservationSite.saved(
        site,
        temporaryTrackingOverride: clearOverrides
            ? null
            : _active.temporaryTrackingOverride,
        temporaryEquipmentOverrideId: clearOverrides
            ? null
            : _active.temporaryEquipmentOverrideId,
      );
    }
    notifyListeners();
  }

  void setTemporaryTrackingOverride(TrackingMode mode) {
    _active = _active.copyWithOverrides(trackingMode: mode);
    notifyListeners();
  }

  void setTemporaryEquipmentOverride(String? equipmentId) {
    _active = _active.copyWithOverrides(
      equipmentId: equipmentId,
      clearEquipment: equipmentId == null,
    );
    notifyListeners();
  }

  ObservationSite? _findSite(String id) {
    for (final site in _sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  void _replaceSite(ObservationSite site) {
    final next = [..._sites];
    final index = next.indexWhere((item) => item.id == site.id);
    if (index == -1) {
      next.add(site);
    } else {
      next[index] = site;
    }
    _sites = _sortSites(next);
  }

  List<ObservationSite> _sortSites(List<ObservationSite> sites) {
    final sorted = [...sites];
    sorted.sort((a, b) {
      final recent = (b.lastUsedAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.lastUsedAt?.millisecondsSinceEpoch ?? 0,
      );
      if (recent != 0) return recent;
      if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }
}
