import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/constants/catalog_sort_order.dart';
import '../../../core/constants/gallery_object_category.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../services/catalog_object_sorter.dart';
import '../../../services/catalog_search_service.dart';

enum GallerySortOrder {
  newestFirst,
  oldestFirst,
  nameAsc,
  shootCountDesc,
}

enum GalleryViewMode { byDate, byObject }

extension GallerySortOrderLabel on GallerySortOrder {
  String get label {
    switch (this) {
      case GallerySortOrder.newestFirst:
        return '최신 촬영순';
      case GallerySortOrder.oldestFirst:
        return '오래된 촬영순';
      case GallerySortOrder.nameAsc:
        return '대상명 가나다순';
      case GallerySortOrder.shootCountDesc:
        return '촬영횟수 많은 순';
    }
  }
}

class DateGroup {
  const DateGroup({required this.date, required this.records});

  final DateTime date;
  final List<ShootingRecord> records;
}

/// 동일 촬영대상 그룹.
class TargetGroup {
  const TargetGroup({
    required this.object,
    required this.representativeRecord,
    required this.photoCount,
    required this.records,
  });

  final CatalogObject object;
  final ShootingRecord representativeRecord;
  final int photoCount;

  /// 사진이 있는 기록, 촬영일 최신순.
  final List<ShootingRecord> records;
}

class GalleryViewModel extends ChangeNotifier {
  GalleryViewModel(
    this._shootingRecordRepository,
    this._catalogRepository,
    this._catalogSearchService,
  );

  final ShootingRecordRepository _shootingRecordRepository;
  final CatalogRepository _catalogRepository;
  final CatalogSearchService _catalogSearchService;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  List<ShootingRecord> _allRecords = [];
  Map<String, CatalogObject> _catalogMap = {};

  GallerySortOrder _sortOrder = GallerySortOrder.newestFirst;
  GalleryViewMode _viewMode = GalleryViewMode.byObject;
  GalleryObjectCategory _categoryFilter = GalleryObjectCategory.all;
  String _searchQuery = '';
  bool _favoritesOnly = false;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  String? _filterLocation;

  List<ShootingRecord>? _cachedPipelineRecords;
  bool _pipelineCacheDirty = true;

  void _invalidatePipelineCache() {
    _pipelineCacheDirty = true;
    _cachedPipelineRecords = null;
  }

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  GallerySortOrder get sortOrder => _sortOrder;
  GalleryViewMode get viewMode => _viewMode;
  GalleryObjectCategory get categoryFilter => _categoryFilter;
  String get searchQuery => _searchQuery;
  bool get favoritesOnly => _favoritesOnly;
  DateTime? get filterDateFrom => _filterDateFrom;
  DateTime? get filterDateTo => _filterDateTo;
  String? get filterLocation => _filterLocation;
  bool get hasActiveFilters =>
      _categoryFilter != GalleryObjectCategory.all ||
      _searchQuery.trim().isNotEmpty ||
      _favoritesOnly ||
      _filterDateFrom != null ||
      _filterDateTo != null ||
      (_filterLocation != null && _filterLocation!.isNotEmpty);

  List<CatalogObject> get allCatalogObjects => List.unmodifiable(
        CatalogObjectSorter.sort(
          _catalogMap.values.toList(),
          CatalogSortOrder.catalogNumber,
        ),
      );

  CatalogObject? catalogObjectFor(String celestialObjectId) =>
      _catalogMap[celestialObjectId];

  List<String> get availableLocations {
    final locations = <String>{};
    for (final record in _allRecords) {
      final label = _locationLabel(record);
      if (label != null) locations.add(label);
    }
    final sorted = locations.toList()..sort();
    return sorted;
  }

  /// 필터 파이프라인을 거친 기록.
  List<ShootingRecord> get _pipelineRecords {
    if (!_pipelineCacheDirty && _cachedPipelineRecords != null) {
      return _cachedPipelineRecords!;
    }

    var records = List<ShootingRecord>.from(_allRecords);

    if (_filterDateFrom != null) {
      records = records
          .where((record) => !_isBeforeDate(record.capturedAt, _filterDateFrom!))
          .toList();
    }

    if (_filterDateTo != null) {
      records = records
          .where((record) => !_isAfterDate(record.capturedAt, _filterDateTo!))
          .toList();
    }

    if (_filterLocation != null && _filterLocation!.isNotEmpty) {
      records = records
          .where((record) => _locationLabel(record) == _filterLocation)
          .toList();
    }

    if (_categoryFilter != GalleryObjectCategory.all) {
      records = records.where((record) {
        final obj = _catalogMap[record.celestialObjectId];
        if (obj == null) {
          return _categoryFilter == GalleryObjectCategory.other;
        }
        return GalleryCategoryMapper.matches(obj, _categoryFilter);
      }).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final matchedIds = _matchedObjectIds(_searchQuery);
      records = records
          .where((r) => matchedIds.contains(r.celestialObjectId))
          .toList();
    }

    if (_favoritesOnly) {
      records = records.where((r) => r.isFavorite).toList();
    }

    _cachedPipelineRecords = records;
    _pipelineCacheDirty = false;
    return records;
  }

  List<ShootingRecord> get filteredRecords {
    final records = List<ShootingRecord>.from(_pipelineRecords);
    records.sort(_compareRecordsByCapturedAt);
    return records;
  }

  /// 대상별 보기: 천체당 대표사진 그룹.
  List<TargetGroup> get targetGroups {
    final map = <String, List<ShootingRecord>>{};

    for (final record in _pipelineRecords) {
      if (record.photoUri == null || record.photoUri!.isEmpty) continue;
      (map[record.celestialObjectId] ??= []).add(record);
    }

    final groups = <TargetGroup>[];
    for (final entry in map.entries) {
      final object = _catalogMap[entry.key];
      if (object == null) continue;

      final records = List<ShootingRecord>.from(entry.value)
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

      var representative = records.first;
      for (final record in records) {
        if (record.isRepresentative) {
          representative = record;
          break;
        }
      }

      groups.add(
        TargetGroup(
          object: object,
          representativeRecord: representative,
          photoCount: records.length,
          records: records,
        ),
      );
    }

    _sortTargetGroups(groups);
    return groups;
  }

  /// 하위 호환 — 대상별 1장 목록.
  List<ShootingRecord> get objectViewRecords =>
      targetGroups.map((g) => g.representativeRecord).toList();

  String? representativePhotoUriFor(String celestialObjectId) {
    final records = _allRecords
        .where((r) => r.celestialObjectId == celestialObjectId)
        .where((r) => r.photoUri != null && r.photoUri!.isNotEmpty)
        .toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    for (final record in records) {
      if (record.isRepresentative) return record.photoUri;
    }
    return records.isNotEmpty ? records.first.photoUri : null;
  }

  int photoCountFor(String celestialObjectId) {
    return _pipelineRecords
        .where((r) => r.celestialObjectId == celestialObjectId)
        .where((r) => r.photoUri != null && r.photoUri!.isNotEmpty)
        .length;
  }

  /// 날짜별 보기 상세 스와이프용.
  List<ShootingRecord> get photoRecordsForGalleryDetail {
    return filteredRecords
        .where((r) => r.photoUri != null && r.photoUri!.isNotEmpty)
        .toList();
  }

  List<DateGroup> get recordsGroupedByDate {
    final records = filteredRecords;
    final map = <String, List<ShootingRecord>>{};

    for (final record in records) {
      final key =
          '${record.capturedAt.year}-${record.capturedAt.month.toString().padLeft(2, '0')}-${record.capturedAt.day.toString().padLeft(2, '0')}';
      (map[key] ??= []).add(record);
    }

    final groups = map.entries.map((entry) {
      final parts = entry.key.split('-');
      return DateGroup(
        date: DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        ),
        records: entry.value,
      );
    }).toList();

    groups.sort((a, b) => _sortOrder == GallerySortOrder.oldestFirst
        ? a.date.compareTo(b.date)
        : b.date.compareTo(a.date));

    return groups;
  }

  Set<String> _matchedObjectIds(String query) {
    final catalogObjects = _catalogMap.values.toList();
    final results = _catalogSearchService.search(query, catalogObjects);
    if (results.isNotEmpty) {
      return results.map((o) => o.id).toSet();
    }

    final lower = query.toLowerCase();
    return catalogObjects
        .where(
          (obj) =>
              obj.displayName.toLowerCase().contains(lower) ||
              obj.displayCommonName.toLowerCase().contains(lower) ||
              obj.aliases.any((a) => a.toLowerCase().contains(lower)) ||
              obj.crossCatalogRefs.any((a) => a.toLowerCase().contains(lower)),
        )
        .map((o) => o.id)
        .toSet();
  }

  int _compareRecordsByCapturedAt(ShootingRecord a, ShootingRecord b) {
    return _sortOrder == GallerySortOrder.oldestFirst
        ? a.capturedAt.compareTo(b.capturedAt)
        : b.capturedAt.compareTo(a.capturedAt);
  }

  void _sortTargetGroups(List<TargetGroup> groups) {
    switch (_sortOrder) {
      case GallerySortOrder.newestFirst:
        groups.sort(
          (a, b) => b.representativeRecord.capturedAt
              .compareTo(a.representativeRecord.capturedAt),
        );
      case GallerySortOrder.oldestFirst:
        groups.sort(
          (a, b) => a.representativeRecord.capturedAt
              .compareTo(b.representativeRecord.capturedAt),
        );
      case GallerySortOrder.nameAsc:
        // 문자열 사전순(M10→M100)이 아니라 카탈로그 번호순(M10→M11→…→M100)
        groups.sort(
          (a, b) => CatalogObjectSorter.compare(
            a.object,
            b.object,
            CatalogSortOrder.catalogNumber,
          ),
        );
      case GallerySortOrder.shootCountDesc:
        groups.sort((a, b) {
          final byCount = b.photoCount.compareTo(a.photoCount);
          if (byCount != 0) return byCount;
          return b.representativeRecord.capturedAt
              .compareTo(a.representativeRecord.capturedAt);
        });
    }
  }

  Future<void> load({bool silent = false}) async {
    if (_isLoading) return;
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final records = await _shootingRecordRepository.getAll();
      final catalogObjects = await _catalogRepository.getAll(listOnly: true);

      _catalogMap = {for (final object in catalogObjects) object.id: object};
      _allRecords = records;
      _invalidatePipelineCache();
      _hasLoaded = true;
      if (silent) _errorMessage = null;
    } catch (error) {
      if (!silent) {
        _errorMessage = error.toString();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSortOrder(GallerySortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    notifyListeners();
  }

  void toggleViewMode() {
    setViewMode(
      _viewMode == GalleryViewMode.byDate
          ? GalleryViewMode.byObject
          : GalleryViewMode.byDate,
    );
  }

  void setViewMode(GalleryViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
  }

  void setCategoryFilter(GalleryObjectCategory category) {
    if (_categoryFilter == category) return;
    _categoryFilter = category;
    _invalidatePipelineCache();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _invalidatePipelineCache();
    notifyListeners();
  }

  void toggleFavoritesOnly() {
    _favoritesOnly = !_favoritesOnly;
    _invalidatePipelineCache();
    notifyListeners();
  }

  void setDateRange({DateTime? from, DateTime? to}) {
    _filterDateFrom = from;
    _filterDateTo = to;
    _invalidatePipelineCache();
    notifyListeners();
  }

  void setLocationFilter(String? location) {
    _filterLocation = location;
    _invalidatePipelineCache();
    notifyListeners();
  }

  void clearFilters() {
    _categoryFilter = GalleryObjectCategory.all;
    _searchQuery = '';
    _favoritesOnly = false;
    _filterDateFrom = null;
    _filterDateTo = null;
    _filterLocation = null;
    _invalidatePipelineCache();
    notifyListeners();
  }

  Future<void> toggleFavorite(ShootingRecord record) async {
    try {
      final updated = record.copyWith(isFavorite: !record.isFavorite);
      await _shootingRecordRepository.update(updated);
      _replaceRecord(updated);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> setRepresentativePhoto(ShootingRecord record) async {
    try {
      await _shootingRecordRepository.setRepresentative(record.id);
      _allRecords = _allRecords
          .map(
            (r) => r.celestialObjectId == record.celestialObjectId
                ? r.copyWith(isRepresentative: r.id == record.id)
                : r,
          )
          .toList();
      _invalidatePipelineCache();
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> deleteRecord(ShootingRecord record) async {
    try {
      if (record.photoUri != null) {
        final file = File(record.photoUri!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
      await _shootingRecordRepository.delete(record.id);
      _allRecords = _allRecords.where((r) => r.id != record.id).toList();
      _invalidatePipelineCache();
      notifyListeners();
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> updateMemo(ShootingRecord record, String newMemo) async {
    try {
      final updated = record.copyWith(memo: newMemo);
      await _shootingRecordRepository.update(updated);
      _replaceRecord(updated);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> updateLocation(ShootingRecord record, String? newLocation) async {
    try {
      final updated = newLocation == null || newLocation.isEmpty
          ? record.copyWith(clearLocation: true)
          : record.copyWith(location: newLocation);
      await _shootingRecordRepository.update(updated);
      _replaceRecord(updated);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> updateTarget(
    ShootingRecord record,
    String newCelestialObjectId,
  ) async {
    try {
      final updated = record.copyWith(celestialObjectId: newCelestialObjectId);
      await _shootingRecordRepository.update(updated);
      _replaceRecord(updated);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> updateRecord(ShootingRecord updatedRecord) async {
    try {
      await _shootingRecordRepository.update(updatedRecord);
      _replaceRecord(updatedRecord);
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
    }
  }

  void _replaceRecord(ShootingRecord updated) {
    _allRecords =
        _allRecords.map((r) => r.id == updated.id ? updated : r).toList();
    _invalidatePipelineCache();
    notifyListeners();
  }

  bool _isBeforeDate(DateTime capturedAt, DateTime filterDate) {
    final from = DateTime(filterDate.year, filterDate.month, filterDate.day);
    return capturedAt.isBefore(from);
  }

  bool _isAfterDate(DateTime capturedAt, DateTime filterDate) {
    final to = DateTime(
      filterDate.year,
      filterDate.month,
      filterDate.day,
      23,
      59,
      59,
      999,
    );
    return capturedAt.isAfter(to);
  }

  String? _locationLabel(ShootingRecord record) {
    final exifName = record.exif?.locationName?.trim();
    if (exifName != null && exifName.isNotEmpty) return exifName;

    final location = record.location?.trim();
    if (location != null && location.isNotEmpty) return location;

    return null;
  }
}
