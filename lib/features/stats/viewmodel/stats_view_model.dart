import 'package:flutter/foundation.dart';

import '../../../data/models/catalog_object.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../services/stats_analytics_service.dart';
import '../../../services/stats_models.dart';

class StatsViewModel extends ChangeNotifier {
  StatsViewModel(
    this._shootingRecordRepository,
    this._catalogRepository,
    this._statsAnalyticsService,
  );

  final ShootingRecordRepository _shootingRecordRepository;
  final CatalogRepository _catalogRepository;
  final StatsAnalyticsService _statsAnalyticsService;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  StatsDashboardData? _dashboard;
  List<ShootingRecord> _records = const [];
  Map<String, CatalogObject> _catalogById = const {};
  List<CatalogCategoryProgress> _categoryProgress = const [];
  int _selectedAchievementYear = DateTime.now().year;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  StatsDashboardData? get dashboard => _dashboard;

  int get selectedAchievementYear => _selectedAchievementYear;
  int get chartYear => _dashboard?.referenceYear ?? DateTime.now().year;

  StatsKpiSummary? get kpi => _dashboard?.kpi;
  List<MonthlyStatsPoint> get monthlyStats =>
      _dashboard?.monthlyStats ?? const [];
  MonthlyHighlight? get currentMonth => _dashboard?.currentMonth;
  List<TopTargetStat> get topTargets => _dashboard?.topTargets ?? const [];
  List<ObjectTypeBreakdown> get typeBreakdown =>
      _dashboard?.typeBreakdown ?? const [];
  List<CatalogCategoryProgress> get categoryProgress => _categoryProgress;

  List<int> get availableAchievementYears =>
      _statsAnalyticsService.listAchievementYears(_records);

  YearAchievementSummary get selectedYearAchievement =>
      _statsAnalyticsService.buildYearAchievement(
        records: _records,
        catalogById: _catalogById,
        year: _selectedAchievementYear,
      );

  void selectAchievementYear(int year) {
    if (year == _selectedAchievementYear) return;
    _selectedAchievementYear = year;
    notifyListeners();
  }

  MonthlyDetailStats monthlyDetail({required int year, required int month}) {
    return _statsAnalyticsService.buildMonthlyDetail(
      records: _records,
      catalogById: _catalogById,
      year: year,
      month: month,
    );
  }

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final records = await _shootingRecordRepository.getAll();
      final catalog = await _catalogRepository.getAll();
      final catalogById = {for (final object in catalog) object.id: object};

      _records = records;
      _catalogById = catalogById;
      _dashboard = _statsAnalyticsService.buildDashboard(
        records: records,
        catalogById: catalogById,
      );
      _categoryProgress = _statsAnalyticsService.buildCategoryProgress(
        records: records,
        catalog: catalog,
      );
      _syncAchievementYear();
      _hasLoaded = true;
    } catch (error) {
      _errorMessage = error.toString();
      _dashboard = null;
      _records = const [];
      _catalogById = const {};
      _categoryProgress = const [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _syncAchievementYear() {
    final available = availableAchievementYears;
    if (available.contains(_selectedAchievementYear)) return;

    final currentYear = DateTime.now().year;
    _selectedAchievementYear = available.contains(currentYear)
        ? currentYear
        : available.first;
  }
}
