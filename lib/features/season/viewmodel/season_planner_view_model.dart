import 'package:flutter/foundation.dart';

import '../../../core/constants/astro_season.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/season_planner_item.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../services/season_planner_filter_service.dart';
import '../../../services/season_planner_service.dart';

enum SeasonPlannerViewMode { bySeason, byMonth }

class SeasonPlannerViewModel extends ChangeNotifier {
  SeasonPlannerViewModel(
    this._catalogRepository,
    this._shootingRecordRepository,
    this._filterService, {
    SeasonPlannerService? seasonPlannerService,
    SeasonPlannerViewMode initialViewMode = SeasonPlannerViewMode.bySeason,
    int? initialMonth,
  }) : _seasonPlannerService =
           seasonPlannerService ?? const SeasonPlannerService(),
       _viewMode = initialViewMode,
       _selectedMonth = initialMonth ?? DateTime.now().month;

  final CatalogRepository _catalogRepository;
  final ShootingRecordRepository _shootingRecordRepository;
  final SeasonPlannerFilterService _filterService;
  final SeasonPlannerService _seasonPlannerService;

  bool _isLoading = false;
  String? _errorMessage;
  List<SeasonPlannerItem> _items = const [];
  final Map<String, String> _thumbnailMap = {};

  SeasonPlannerViewMode _viewMode;
  AstroSeason _selectedSeason = AstroSeason.fromMonth(DateTime.now().month);
  int _selectedMonth;
  bool _uncapturedOnly = false;
  Set<CatalogType> _catalogFilters = {};

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<SeasonPlannerItem> get items => List.unmodifiable(_items);
  SeasonPlannerViewMode get viewMode => _viewMode;
  AstroSeason get selectedSeason => _selectedSeason;
  int get selectedMonth => _selectedMonth;
  bool get uncapturedOnly => _uncapturedOnly;
  Set<CatalogType> get catalogFilters => Set.unmodifiable(_catalogFilters);
  bool get hasCatalogFilter => _catalogFilters.isNotEmpty;

  int get uncapturedCount => _items.where((i) => !i.object.captured).length;
  int get capturedCount => _items.length - uncapturedCount;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _catalogFilters = await _filterService.load();
      final objects = await _catalogRepository.getAll();
      final records = await _shootingRecordRepository.getAll();
      _buildThumbnailMap(records);
      _rebuildItems(objects);
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setViewMode(SeasonPlannerViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _refreshItems();
  }

  void selectSeason(AstroSeason season) {
    if (_selectedSeason == season) return;
    _selectedSeason = season;
    _refreshItems();
  }

  void selectMonth(int month) {
    if (_selectedMonth == month) return;
    _selectedMonth = month;
    _refreshItems();
  }

  void setUncapturedOnly(bool value) {
    if (_uncapturedOnly == value) return;
    _uncapturedOnly = value;
    _refreshItems();
  }

  void toggleCatalogFilter(CatalogType catalog) {
    final all = SeasonPlannerService.plannerCatalogTypes.toSet();
    Set<CatalogType> next;

    if (_catalogFilters.isEmpty) {
      next = Set<CatalogType>.from(all)..remove(catalog);
    } else if (_catalogFilters.contains(catalog)) {
      next = Set<CatalogType>.from(_catalogFilters)..remove(catalog);
    } else {
      next = Set<CatalogType>.from(_catalogFilters)..add(catalog);
      if (next.length == all.length) {
        next = {};
      }
    }

    if (setEquals(next, _catalogFilters)) return;
    _catalogFilters = next;
    _persistFilters();
    _refreshItems();
  }

  void clearCatalogFilters() {
    if (_catalogFilters.isEmpty) return;
    _catalogFilters = {};
    _persistFilters();
    _refreshItems();
  }

  void _persistFilters() {
    _filterService.save(_catalogFilters);
  }

  Future<void> _refreshItems() async {
    try {
      final objects = await _catalogRepository.getAll();
      _rebuildItems(objects);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  void _rebuildItems(List<CatalogObject> objects) {
    _items = _seasonPlannerService.buildItems(
      objects: objects,
      month: _selectedMonth,
      season: _viewMode == SeasonPlannerViewMode.bySeason
          ? _selectedSeason
          : null,
      uncapturedOnly: _uncapturedOnly,
      catalogFilters: _catalogFilters.isEmpty ? null : _catalogFilters,
      thumbnails: _thumbnailMap,
    );
    notifyListeners();
  }

  void _buildThumbnailMap(List<ShootingRecord> records) {
    _thumbnailMap.clear();
    final sorted = [...records]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    for (final record in sorted) {
      if (record.photoUri == null || record.photoUri!.isEmpty) continue;
      if (!record.isRepresentative) continue;
      _thumbnailMap[record.celestialObjectId] = record.photoUri!;
    }

    for (final record in sorted) {
      if (record.photoUri == null || record.photoUri!.isEmpty) continue;
      _thumbnailMap.putIfAbsent(
        record.celestialObjectId,
        () => record.photoUri!,
      );
    }
  }
}
