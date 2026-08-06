import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/catalog_kind_filter.dart';
import '../../../core/constants/catalog_sort_order.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../data/models/catalog_equipment_chips.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../services/catalog_object_sorter.dart';
import '../../../services/catalog_search_index.dart';
import '../../../services/catalog_search_service.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';

enum ShootingFilter { all, captured, notCaptured }

class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel(
    this._catalogRepository,
    this._shootingRecordRepository,
    this._equipmentRepository,
    this._equipmentRecommendationService,
  );

  final CatalogRepository _catalogRepository;
  final ShootingRecordRepository _shootingRecordRepository;
  final EquipmentRepository _equipmentRepository;
  final EquipmentRecommendationService _equipmentRecommendationService;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  List<CatalogObject> _allObjects = [];
  List<CatalogObject>? _visibleObjects;
  CatalogSearchIndex? _searchIndex;
  CatalogType? _selectedTab; // null = 전체
  ShootingFilter _shootingFilter = ShootingFilter.all;
  CatalogKindFilter _kindFilter = CatalogKindFilter.all;
  CatalogSortOrder _sortOrder = CatalogSortOrder.defaultOrder;

  /// 천체 ID → 가장 최근 촬영 사진 경로
  final Map<String, String> _thumbnailMap = {};

  /// 천체 ID → 장비 Chip (일반 적합성 기준).
  final Map<String, CatalogEquipmentChips> _equipmentChipsMap = {};

  String? _equipmentChipsCacheKey;
  int _equipmentChipsGeneration = 0;
  int _objectsRevision = 0;
  List<CatalogObject>? _pendingHeavyObjects;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  int get objectsRevision => _objectsRevision;
  String? get errorMessage => _errorMessage;
  CatalogType? get selectedTab => _selectedTab;
  ShootingFilter get shootingFilter => _shootingFilter;
  CatalogKindFilter get kindFilter => _kindFilter;
  CatalogSortOrder get sortOrder => _sortOrder;

  /// 탭/필터 없이 전체 목록 (검색용)
  List<CatalogObject> get allObjects => List.unmodifiable(_allObjects);

  CatalogSearchIndex? get searchIndex => _searchIndex;

  /// 시작 시 썸네일 프리캐시용 (최근 촬영 경로).
  List<String> get previewThumbnailPaths =>
      _thumbnailMap.values.take(32).toList(growable: false);

  CatalogObject resolveForNavigation(CatalogObject object) {
    final resolved =
        CatalogSearchService.resolvePrimaryFromList(object, _allObjects);
    for (final candidate in _allObjects) {
      if (candidate.id == resolved.id) {
        return candidate;
      }
    }
    return resolved;
  }

  /// 상세 화면 스와이프 목록. 현재 필터에 없는 천체는 앞에 붙인다.
  List<CatalogObject> navigationTargetsFor(CatalogObject object) {
    final resolved = resolveForNavigation(object);
    final current = objects;
    if (current.any((candidate) => candidate.id == resolved.id)) {
      return current;
    }
    return [resolved, ...current];
  }

  /// 검색 결과 탭 후 상세 화면용. 선택한 천체가 항상 첫 페이지가 되도록 한다.
  List<CatalogObject> navigationTargetsForSearch(CatalogObject object) {
    final resolved = resolveForNavigation(object);
    final current = objects;
    final rest =
        current.where((candidate) => candidate.id != resolved.id).toList();
    return [resolved, ...rest];
  }

  String? thumbnailFor(String celestialObjectId) =>
      _thumbnailMap[celestialObjectId];

  CatalogEquipmentChips equipmentChipsFor(String celestialObjectId) =>
      _equipmentChipsMap[celestialObjectId] ?? const CatalogEquipmentChips();

  /// 필터·정렬이 적용된 목록. 스크롤 중 재계산하지 않도록 캐시한다.
  List<CatalogObject> get objects =>
      _visibleObjects ??= _computeVisibleObjects();

  List<CatalogObject> _computeVisibleObjects() {
    Iterable<CatalogObject> filtered =
        _allObjects.where((object) => object.isPrimaryCatalog);

    if (_selectedTab != null) {
      filtered = filtered.where((o) => o.catalog == _selectedTab);
    }

    if (_shootingFilter == ShootingFilter.captured) {
      filtered = filtered.where((o) => o.captured);
    } else if (_shootingFilter == ShootingFilter.notCaptured) {
      filtered = filtered.where((o) => !o.captured);
    }

    if (_kindFilter != CatalogKindFilter.all) {
      filtered = filtered.where(
        (o) => _kindFilter.matches(o.resolvedObjectType),
      );
    }

    return CatalogObjectSorter.sort(filtered, _sortOrder);
  }

  void _invalidateVisibleObjects() {
    _visibleObjects = null;
  }

  void selectTab(CatalogType? type) {
    if (_selectedTab == type) return;
    _selectedTab = type;
    _invalidateVisibleObjects();
    notifyListeners();
  }

  void selectShootingFilter(ShootingFilter filter) {
    if (_shootingFilter == filter) return;
    _shootingFilter = filter;
    _invalidateVisibleObjects();
    notifyListeners();
  }

  void selectKindFilter(CatalogKindFilter filter) {
    if (_kindFilter == filter) return;
    _kindFilter = filter;
    _invalidateVisibleObjects();
    notifyListeners();
  }

  void selectSortOrder(CatalogSortOrder order) {
    if (_sortOrder == order) return;
    _sortOrder = order;
    _invalidateVisibleObjects();
    notifyListeners();
  }

  Future<void> load({
    bool silent = false,
    bool deferHeavyWork = false,
  }) async {
    if (_isLoading) return;
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final sw = Stopwatch()..start();
      final objects = await _catalogRepository.getAll(listOnly: true);
      final records = await _shootingRecordRepository.getAll();
      _allObjects = objects;
      _objectsRevision++;
      _invalidateVisibleObjects();
      _buildThumbnailMap(records);
      debugPrint(
        '[CatalogVM] list+thumbnails: ${sw.elapsedMilliseconds}ms '
        '(${objects.length} objects)',
      );
      if (silent) _errorMessage = null;
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();

      // 검색 인덱스·장비 칩은 목록 표시 후.
      // 스플래시 중에는 아예 시작하지 않아 하늘 애니메이션이 끊기지 않게 한다.
      if (deferHeavyWork) {
        _pendingHeavyObjects = objects;
        return;
      }
      await _finishHeavyLoad(objects, sw);
    } catch (error) {
      if (!silent) {
        _errorMessage = error.toString();
      }
      _isLoading = false;
    }
    if (!deferHeavyWork) {
      notifyListeners();
    }
  }

  /// 스플래시 종료 후 검색 인덱스·장비 칩을 구축한다.
  Future<void> finishDeferredHeavyWork() async {
    final objects = _pendingHeavyObjects;
    if (objects == null) return;
    _pendingHeavyObjects = null;
    await _finishHeavyLoad(objects, Stopwatch()..start());
  }

  Future<void> _finishHeavyLoad(List<CatalogObject> objects, Stopwatch sw) async {
    _searchIndex = await CatalogSearchIndex.buildAsync(
      objects,
      globalAliases: CatalogSearchService.globalAliases,
      globalCrossCatalog: CatalogSearchService.globalCrossCatalog,
      chunkSize: 80,
    );
    CatalogSearchService.adoptIndex(_searchIndex!, objects);
    debugPrint('[CatalogVM] search index: ${sw.elapsedMilliseconds}ms');

    await _buildEquipmentChipsMap(
      objects.where((object) => object.isPrimaryCatalog).toList(),
    );
    debugPrint('[CatalogVM] equipment chips: ${sw.elapsedMilliseconds}ms');
    notifyListeners();
  }

  Future<void> _buildEquipmentChipsMap(List<CatalogObject> objects) async {
    final equipment = await _equipmentRepository.getAll(activeOnly: true);
    final cacheKey =
        '$_objectsRevision|${equipment.map((item) => item.id).join(',')}';
    if (cacheKey == _equipmentChipsCacheKey && _equipmentChipsMap.isNotEmpty) {
      return;
    }
    _equipmentChipsCacheKey = cacheKey;

    final generation = ++_equipmentChipsGeneration;
    if (equipment.isEmpty) {
      _equipmentChipsMap.clear();
      return;
    }

    final next = <String, CatalogEquipmentChips>{};
    const chunkSize = 48;
    for (var i = 0; i < objects.length; i++) {
      if (generation != _equipmentChipsGeneration) return;

      final object = objects[i];
      final recommendation = _equipmentRecommendationService.recommendForObject(
        object: object,
        equipment: equipment,
      );
      final chips = CatalogEquipmentChips.fromRecommendation(recommendation);
      if (!chips.isEmpty) {
        next[object.id] = chips;
      }

      if (i % chunkSize == chunkSize - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (generation != _equipmentChipsGeneration) return;
    _equipmentChipsMap
      ..clear()
      ..addAll(next);
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

  /// 사진 등록 후 전체 reload 없이 촬영 상태·썸네일만 반영한다.
  void applyCaptureFromRegistration({
    required String celestialObjectId,
    required String photoUri,
    required DateTime capturedAt,
  }) {
    final dateStr =
        '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')}';

    for (var i = 0; i < _allObjects.length; i++) {
      if (_allObjects[i].id != celestialObjectId) continue;
      _allObjects[i] = _allObjects[i].copyWith(
        captured: true,
        capturedDate: dateStr,
      );
      break;
    }

    if (photoUri.isNotEmpty) {
      _thumbnailMap[celestialObjectId] = photoUri;
    }
    _invalidateVisibleObjects();
    notifyListeners();
  }
}
