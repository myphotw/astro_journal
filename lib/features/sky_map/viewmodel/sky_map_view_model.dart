import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/constants/constellation_names.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/fov_box.dart';
import '../../../data/models/sky_map_constellation.dart';
import '../../../data/models/sky_map_render_object.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/sky_map/sky_map_constellation_catalog.dart';
import '../../../data/sky_map/sky_map_star_names_ko.dart';
import '../../../services/celestial_position_service.dart';
import '../../../services/equipment/fov_framing_engine.dart';
import '../../../services/sky_map_angular_size.dart';
import '../../../services/sky_map_projection_service.dart';
import '../widgets/sky_map_object_symbol.dart';

/// 별자리 BottomSheet용 Catalog 필터 (다중 선택, '전체' 없음).
enum ConstellationCatalogFilter {
  messier('Messier'),
  ngc('NGC'),
  ic('IC'),
  sh2('Sh2'),
  caldwell('Caldwell'),
  other('기타');

  const ConstellationCatalogFilter(this.label);

  final String label;

  static const allFilters = ConstellationCatalogFilter.values;

  bool matches(CatalogObject object) {
    return switch (this) {
      ConstellationCatalogFilter.messier =>
        object.catalog == CatalogType.messier,
      ConstellationCatalogFilter.ngc => object.catalog == CatalogType.ngc,
      ConstellationCatalogFilter.ic => object.catalog == CatalogType.ic,
      ConstellationCatalogFilter.sh2 => object.catalog == CatalogType.sh2,
      ConstellationCatalogFilter.caldwell =>
        object.catalog == CatalogType.caldwell,
      ConstellationCatalogFilter.other =>
        object.catalog != CatalogType.messier &&
            object.catalog != CatalogType.ngc &&
            object.catalog != CatalogType.ic &&
            object.catalog != CatalogType.sh2 &&
            object.catalog != CatalogType.caldwell,
    };
  }
}

/// 성도 필터 상태.
class SkyMapFilters {
  /// 초기 표시는 Messier만. NGC/IC/Sh2는 필터로 켠다.
  /// 종류 필터는 범례(은하·산개·구상·성운·행성상)와 동일.
  const SkyMapFilters({
    this.catalogs = const {
      CatalogType.messier,
    },
    this.objectTypes = const {
      SkyMapObjectTypeFilter.galaxy,
      SkyMapObjectTypeFilter.openCluster,
      SkyMapObjectTypeFilter.globularCluster,
      SkyMapObjectTypeFilter.nebula,
      SkyMapObjectTypeFilter.planetaryNebula,
    },
    this.showConstellations = true,
    this.showBrightStars = true,
  });

  final Set<CatalogType> catalogs;
  final Set<SkyMapObjectTypeFilter> objectTypes;
  final bool showConstellations;
  final bool showBrightStars;

  static const supportedCatalogs = <CatalogType>[
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
    CatalogType.caldwell,
  ];

  /// 별자리 목록·탐색에 포함할 Catalog (지도 필터보다 넓음).
  static const constellationQueryCatalogs = <CatalogType>[
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
    CatalogType.caldwell,
    CatalogType.rcw,
    CatalogType.vdb,
    CatalogType.barnard,
    CatalogType.ldn,
    CatalogType.lbn,
  ];

  static const supportedObjectTypes = SkyMapObjectTypeFilter.legendFilters;

  static const double brightStarMagLimit = 4.5;

  bool matches(CatalogObject object) {
    if (!catalogs.contains(object.catalog)) return false;
    if (objectTypes.isEmpty) return true;
    final type = object.resolvedObjectType;
    final filter = SkyMapObjectTypeFilter.forObjectType(type);
    // 범례에 없는 유형은 통과(희귀)
    if (filter == null) return true;
    return objectTypes.contains(filter);
  }

  SkyMapFilters copyWith({
    Set<CatalogType>? catalogs,
    Set<SkyMapObjectTypeFilter>? objectTypes,
    bool? showConstellations,
    bool? showBrightStars,
  }) {
    return SkyMapFilters(
      catalogs: catalogs ?? this.catalogs,
      objectTypes: objectTypes ?? this.objectTypes,
      showConstellations: showConstellations ?? this.showConstellations,
      showBrightStars: showBrightStars ?? this.showBrightStars,
    );
  }
}

class SkyMapFramingAdvice {
  const SkyMapFramingAdvice({
    required this.coverage,
    required this.tips,
    required this.recommendation,
  });

  final FramingCoverageResult coverage;
  final List<String> tips;
  final FramingRecommendation recommendation;
}

class SkyMapViewModel extends ChangeNotifier {
  SkyMapViewModel(
    this._catalogRepository,
    this._equipmentRepository,
  );

  final CatalogRepository _catalogRepository;
  final EquipmentRepository _equipmentRepository;

  static const double minViewHeightDeg = 4;
  static const double maxViewHeightDeg = 180;
  static const double defaultViewHeightDeg = 90;
  static const double defaultCenterRaDeg = 80;
  static const double defaultCenterDecDeg = 20;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<CatalogObject> _deepSkyObjects = [];
  List<CatalogObject> _constellationCatalogObjects = [];
  List<Equipment> _equipment = [];
  SkyMapFilters _filters = const SkyMapFilters();
  String _searchQuery = '';

  double _centerRaDeg = defaultCenterRaDeg;
  double _centerDecDeg = defaultCenterDecDeg;
  double _viewHeightDeg = defaultViewHeightDeg;
  Size _canvasSize = Size.zero;

  CatalogObject? _selectedObject;
  FovPreview? _fovPreview;
  bool _showFovOverlay = false;

  List<SkyMapRenderObject> _visibleObjects = [];
  List<SkyMapStarRender> _visibleStars = [];
  List<SkyMapConstellationRender> _visibleConstellations = [];

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  SkyMapFilters get filters => _filters;
  String get searchQuery => _searchQuery;
  double get centerRaDeg => _centerRaDeg;
  double get centerDecDeg => _centerDecDeg;
  double get viewHeightDeg => _viewHeightDeg;
  Size get canvasSize => _canvasSize;
  CatalogObject? get selectedObject => _selectedObject;
  FovPreview? get fovPreview => _fovPreview;
  bool get showFovOverlay => _showFovOverlay;
  List<SkyMapRenderObject> get visibleObjects =>
      List.unmodifiable(_visibleObjects);
  List<SkyMapStarRender> get visibleStars => List.unmodifiable(_visibleStars);
  List<SkyMapConstellationRender> get visibleConstellations =>
      List.unmodifiable(_visibleConstellations);
  List<Equipment> get imagingEquipment => _equipment
      .where((e) => e.isActive && e.hasFov)
      .toList(growable: false);

  SkyMapRenderObject? get selectedRenderObject {
    final selected = _selectedObject;
    if (selected == null) return null;
    for (final obj in _visibleObjects) {
      if (obj.catalogId == selected.id) return obj;
    }
    return null;
  }

  List<Offset> get fovCorners {
    final fov = _fovPreview;
    final selected = _selectedObject;
    if (!_showFovOverlay || fov == null || selected == null) {
      return const [];
    }
    if (_canvasSize == Size.zero || !fov.isValid) return const [];
    final ra = CelestialPositionService.parseRaHours(selected.ra) * 15;
    final dec = CelestialPositionService.parseDecDeg(selected.dec);
    return SkyMapProjectionService.projectFovCorners(
      objectRaDeg: ra,
      objectDecDeg: dec,
      centerRaDeg: _centerRaDeg,
      centerDecDeg: _centerDecDeg,
      fovWidthDeg: fov.widthDegrees,
      fovHeightDeg: fov.heightDegrees,
      rotationDeg: fov.rotationDegrees,
      canvasSize: _canvasSize,
      viewHeightDeg: _viewHeightDeg,
    );
  }

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final all = await _catalogRepository.getAll(listOnly: true);

      _deepSkyObjects = all
          .where(
            (o) =>
                o.isPrimaryCatalog &&
                SkyMapFilters.supportedCatalogs.contains(o.catalog),
          )
          .toList(growable: false);

      _constellationCatalogObjects = all
          .where(
            (o) =>
                o.isPrimaryCatalog &&
                SkyMapFilters.constellationQueryCatalogs.contains(o.catalog),
          )
          .toList(growable: false);

      _equipment = await _equipmentRepository.getAll(activeOnly: true);
      _hasLoaded = true;
      _rebuildVisible();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateCanvasSize(Size size) {
    if (size == _canvasSize || size.isEmpty) return;
    _canvasSize = size;
    _rebuildVisible();
    notifyListeners();
  }

  void setFilters(SkyMapFilters filters) {
    _filters = filters;
    _rebuildVisible();
    notifyListeners();
  }

  void toggleCatalog(CatalogType type) {
    final next = Set<CatalogType>.from(_filters.catalogs);
    if (next.contains(type)) {
      if (next.length == 1) return;
      next.remove(type);
    } else {
      next.add(type);
    }
    setFilters(_filters.copyWith(catalogs: next));
  }

  void toggleObjectType(SkyMapObjectTypeFilter type) {
    final next = Set<SkyMapObjectTypeFilter>.from(_filters.objectTypes);
    if (next.contains(type)) {
      if (next.length == 1) return;
      next.remove(type);
    } else {
      next.add(type);
    }
    setFilters(_filters.copyWith(objectTypes: next));
  }

  void setShowConstellations(bool value) {
    setFilters(_filters.copyWith(showConstellations: value));
  }

  void setShowBrightStars(bool value) {
    setFilters(_filters.copyWith(showBrightStars: value));
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim();
    _rebuildVisible();
    notifyListeners();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    _rebuildVisible();
    notifyListeners();
  }

  /// 세로 시야가 전천(±90°)을 덮으면 적위 pan 불필요 → 0으로 고정.
  double get _maxCenterDecDeg =>
      math.max(0.0, 90.0 - _viewHeightDeg / 2);

  bool _visibleRebuildScheduled = false;

  void panByPixels(Offset delta) {
    if (_canvasSize == Size.zero) return;
    final dpp = SkyMapProjectionService.degreesPerPixel(
      canvasSize: _canvasSize,
      viewHeightDeg: _viewHeightDeg,
    );
    // plate carrée: RA도 Dec와 동일 °/px (cosDec 없음 → 남북 드래그 시 줌 착시 방지)
    _centerRaDeg = (_centerRaDeg - delta.dx * dpp) % 360;
    if (_centerRaDeg < 0) _centerRaDeg += 360;

    final maxDec = _maxCenterDecDeg;
    if (maxDec <= 0) {
      // 한 화면에 남북 전천이 들어오면 상하 이동 고정
      _centerDecDeg = 0;
    } else if (delta.dy != 0) {
      _centerDecDeg = (_centerDecDeg + delta.dy * dpp).clamp(-maxDec, maxDec);
    }
    _scheduleVisibleRebuild();
  }

  void setViewHeightDeg(double degrees) {
    _viewHeightDeg = degrees.clamp(minViewHeightDeg, maxViewHeightDeg);
    final maxDec = _maxCenterDecDeg;
    _centerDecDeg = maxDec <= 0 ? 0.0 : _centerDecDeg.clamp(-maxDec, maxDec);
    _scheduleVisibleRebuild();
  }

  /// 제스처 이벤트마다 전체 투영을 돌리지 않고 프레임당 1회로 합친다.
  void _scheduleVisibleRebuild() {
    if (_visibleRebuildScheduled) return;
    _visibleRebuildScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _visibleRebuildScheduled = false;
      _rebuildVisible();
      notifyListeners();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void resetView() {
    _centerRaDeg = defaultCenterRaDeg;
    _centerDecDeg = defaultCenterDecDeg;
    _viewHeightDeg = defaultViewHeightDeg;
    _rebuildVisible();
    notifyListeners();
  }

  void selectObject(CatalogObject? object) {
    _selectedObject = object;
    if (object != null) {
      _centerRaDeg = CelestialPositionService.parseRaHours(object.ra) * 15;
      _centerDecDeg = CelestialPositionService.parseDecDeg(object.dec);
      final major = object.majorAxis;
      final axes = SkyMapAngularSize.resolveArcmin(object);
      final sizeMajor = axes?.major ?? major;
      if (sizeMajor != null && sizeMajor > 0) {
        // 대상이 화면의 ~1/4~1/3을 차지하도록 줌
        final targetDeg = (sizeMajor / 60) * 4;
        _viewHeightDeg = targetDeg.clamp(8.0, 50.0);
      } else if (_viewHeightDeg > 45) {
        _viewHeightDeg = 30;
      }
      _rebuildVisible();
    }
    notifyListeners();
  }

  /// 외부(홈·카탈로그)에서 성도로 진입할 때 — 위치만 포커스, 상세 시트는 열지 않음.
  void focusObjectLocation(CatalogObject object) {
    _ensureObjectVisibleInFilters(object);
    selectObject(object);
  }

  void _ensureObjectVisibleInFilters(CatalogObject object) {
    var changed = false;
    final catalogs = Set<CatalogType>.from(_filters.catalogs);
    if (SkyMapFilters.supportedCatalogs.contains(object.catalog) &&
        !catalogs.contains(object.catalog)) {
      catalogs.add(object.catalog);
      changed = true;
    }

    final objectTypes = Set<SkyMapObjectTypeFilter>.from(_filters.objectTypes);
    final needed =
        SkyMapObjectTypeFilter.forObjectType(object.resolvedObjectType);
    if (needed != null && !objectTypes.contains(needed)) {
      objectTypes.add(needed);
      changed = true;
    }

    if (changed) {
      _filters =
          _filters.copyWith(catalogs: catalogs, objectTypes: objectTypes);
    }
  }

  SkyMapRenderObject? hitTest(Offset position) {
    SkyMapRenderObject? best;
    var bestDist = double.infinity;
    for (final obj in _visibleObjects) {
      final dx = obj.screenX - position.dx;
      final dy = obj.screenY - position.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final hitRadius =
          math.max(math.max(obj.renderWidth, obj.renderHeight) / 2, 18);
      if (dist <= hitRadius && dist < bestDist) {
        bestDist = dist;
        best = obj;
      }
    }
    return best;
  }

  /// 별자리 이름 라벨만 히트 (연결선은 대상 아님).
  SkyMapConstellationRender? hitTestConstellationLabel(Offset position) {
    for (final c in _visibleConstellations) {
      if (c.labelHitRect.contains(position)) return c;
    }
    return null;
  }

  /// [constellationName]에 속한 Catalog 천체 목록 (종류·이름 순).
  ///
  /// 성도 지도 필터와 무관하게 주요 DSO Catalog를 대상으로 한다.
  List<CatalogObject> objectsInConstellation(
    String constellationName, {
    Set<ConstellationCatalogFilter>? catalogs,
    Set<SkyMapObjectTypeFilter>? objectTypes,
  }) {
    final target = ConstellationNames.normalize(constellationName);
    if (target.isEmpty || target == '-') return const [];

    final catalogFilters =
        catalogs ?? ConstellationCatalogFilter.allFilters.toSet();
    final typeFilters =
        objectTypes ?? SkyMapObjectTypeFilter.legendFilters.toSet();

    final list = _constellationCatalogObjects
        .where(
          (o) => ConstellationNames.normalize(o.constellation) == target,
        )
        .where((o) => catalogFilters.any((f) => f.matches(o)))
        .where((o) {
          final type = SkyMapObjectTypeFilter.forObjectType(o.resolvedObjectType);
          // 범례에 없는 유형은 통과(희귀)
          if (type == null) return true;
          return typeFilters.contains(type);
        })
        .toList();
    list.sort((a, b) {
      final typeCmp =
          a.resolvedObjectType.label.compareTo(b.resolvedObjectType.label);
      if (typeCmp != 0) return typeCmp;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  void clearSelection() {
    _selectedObject = null;
    _showFovOverlay = false;
    notifyListeners();
  }

  void showFovForEquipment(Equipment equipment) {
    if (!equipment.hasFov) return;
    final normalized = SkyMapAngularSize.normalizeEquipmentFovDeg(
      width: equipment.fovWidthDegrees!,
      height: equipment.fovHeightDegrees!,
    );
    _fovPreview = FovPreview(
      equipmentId: equipment.id,
      equipmentName: equipment.name,
      widthDegrees: normalized.widthDeg,
      heightDegrees: normalized.heightDeg,
      rotationDegrees: _fovPreview?.rotationDegrees ?? 0,
    );
    _showFovOverlay = true;
    notifyListeners();
  }

  void setFovRotation(double degrees) {
    final fov = _fovPreview;
    if (fov == null) return;
    var normalized = degrees;
    if (normalized < 0) normalized = 0;
    if (normalized > 180) normalized = 180;
    _fovPreview = fov.copyWith(rotationDegrees: normalized);
    notifyListeners();
  }

  void hideFovOverlay() {
    _showFovOverlay = false;
    notifyListeners();
  }

  SkyMapFramingAdvice? framingAdviceFor(Equipment equipment) {
    final object = _selectedObject;
    if (object == null || !equipment.hasFov) return null;

    final axes = SkyMapAngularSize.resolveArcmin(object);
    final major = axes?.major ?? 10;
    final minor = axes?.minor ?? major;
    final normalized = SkyMapAngularSize.normalizeEquipmentFovDeg(
      width: equipment.fovWidthDegrees!,
      height: equipment.fovHeightDegrees!,
    );
    final target = TargetBox.fromArcmin(
      widthArcmin: major,
      heightArcmin: minor,
      positionAngleDegrees: object.positionAngle,
    );
    final fov = FovBox(
      widthDegrees: normalized.widthDeg,
      heightDegrees: normalized.heightDeg,
    );
    final coverage = FovFramingEngine.evaluateBestRotation(
      target: target,
      fov: fov,
    );

    final tips = <String>[];
    final isLandscapePreferred = coverage.bestAngleDegrees < 45 ||
        coverage.bestAngleDegrees > 135;
    if (major >= minor) {
      tips.add(isLandscapePreferred ? '가로 방향 촬영' : '세로 방향 촬영');
    } else {
      tips.add(isLandscapePreferred ? '세로 방향 촬영' : '가로 방향 촬영');
    }

    switch (coverage.recommendation) {
      case FramingRecommendation.good:
        tips.add('대상이 FOV 안에 여유롭게 들어옴');
      case FramingRecommendation.optimal:
        tips.add('최적 프레이밍');
      case FramingRecommendation.tight:
        tips.add('대상 일부 Crop 가능');
      case FramingRecommendation.mosaicRequired:
        tips.add('Mosaic 추천');
    }

    return SkyMapFramingAdvice(
      coverage: coverage,
      tips: tips,
      recommendation: coverage.recommendation,
    );
  }

  /// Catalog 천체 · 별 · 별자리 통합 검색.
  List<SkyMapSearchResult> searchResults(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final results = <SkyMapSearchResult>[];

    for (final figure in SkyMapConstellationCatalog.constellations) {
      final hay =
          '${figure.name} ${figure.nameEn} ${figure.id}'.toLowerCase();
      if (!hay.contains(q)) continue;
      final center = _constellationCenter(figure);
      if (center == null) continue;
      results.add(
        SkyMapSearchResult(
          kind: SkyMapSearchKind.constellation,
          id: figure.id,
          title: figure.name,
          subtitle: figure.nameEn,
          raDeg: center.$1,
          decDeg: center.$2,
        ),
      );
      if (results.length >= 40) return results;
    }

    for (final star in SkyMapConstellationCatalog.stars) {
      final hay = SkyMapStarNamesKo.searchHaystack(
        name: star.name,
        nameKo: star.nameKo,
        id: star.id,
      );
      if (!hay.contains(q)) continue;
      final title = SkyMapStarNamesKo.displayName(
        star.name,
        fallbackKo: star.nameKo,
      );
      final subtitle = title == star.name
          ? 'mag ${star.magnitude.toStringAsFixed(1)}'
          : '${star.name} · mag ${star.magnitude.toStringAsFixed(1)}';
      results.add(
        SkyMapSearchResult(
          kind: SkyMapSearchKind.star,
          id: star.id,
          title: title,
          subtitle: subtitle,
          raDeg: star.raDeg,
          decDeg: star.decDeg,
        ),
      );
      if (results.length >= 40) return results;
    }

    for (final obj in _deepSkyObjects) {
      if (!_filters.matches(obj)) continue;
      final hay = '${obj.displayName} ${obj.displayCommonName} ${obj.name}'
          .toLowerCase();
      if (!hay.contains(q)) continue;
      final ra = CelestialPositionService.parseRaHours(obj.ra) * 15;
      final dec = CelestialPositionService.parseDecDeg(obj.dec);
      results.add(
        SkyMapSearchResult(
          kind: SkyMapSearchKind.catalog,
          id: obj.id,
          title: obj.displayName,
          subtitle: obj.displayCommonName,
          raDeg: ra,
          decDeg: dec,
          catalogObject: obj,
        ),
      );
      if (results.length >= 40) break;
    }

    return results;
  }

  /// 검색 결과로 성도 중심 이동 (별 / 별자리).
  void focusOnSkyPosition({
    required double raDeg,
    required double decDeg,
    double? preferredViewHeightDeg,
  }) {
    _centerRaDeg = raDeg % 360;
    if (_centerRaDeg < 0) _centerRaDeg += 360;
    final maxDec = _maxCenterDecDeg;
    _centerDecDeg =
        maxDec <= 0 ? 0.0 : decDeg.clamp(-maxDec, maxDec);
    if (preferredViewHeightDeg != null) {
      _viewHeightDeg =
          preferredViewHeightDeg.clamp(minViewHeightDeg, maxViewHeightDeg);
    } else if (_viewHeightDeg > 60) {
      _viewHeightDeg = 45;
    }
    final maxDecAfter = _maxCenterDecDeg;
    _centerDecDeg =
        maxDecAfter <= 0 ? 0.0 : _centerDecDeg.clamp(-maxDecAfter, maxDecAfter);
    _rebuildVisible();
    notifyListeners();
  }

  (double, double)? _constellationCenter(SkyMapConstellation figure) {
    final stars = <SkyMapStar>[];
    for (final id in figure.starIds) {
      final s = SkyMapConstellationCatalog.starsById[id];
      if (s != null) stars.add(s);
    }
    if (stars.isEmpty) return null;

    // RA wrap 고려: 첫 별을 기준으로 최단 호 평균
    final refRa = stars.first.raDeg;
    var sumRa = 0.0;
    var sumDec = 0.0;
    for (final s in stars) {
      sumRa += refRa + SkyMapProjectionService.deltaRaDeg(s.raDeg, refRa);
      sumDec += s.decDeg;
    }
    var ra = (sumRa / stars.length) % 360;
    if (ra < 0) ra += 360;
    return (ra, sumDec / stars.length);
  }

  void _rebuildVisible() {
    if (_canvasSize == Size.zero) {
      _visibleObjects = const [];
      _visibleStars = const [];
      _visibleConstellations = const [];
      return;
    }

    _rebuildCatalogObjects();
    _rebuildStars();
    _rebuildConstellations();
  }

  void _rebuildCatalogObjects() {
    final query = _searchQuery.toLowerCase();
    const margin = 80.0;
    final result = <SkyMapRenderObject>[];

    for (final obj in _deepSkyObjects) {
      if (!_filters.matches(obj)) continue;
      if (query.isNotEmpty) {
        final hay =
            '${obj.displayName} ${obj.displayCommonName} ${obj.name}'
                .toLowerCase();
        if (!hay.contains(query)) continue;
      }

      final ra = CelestialPositionService.parseRaHours(obj.ra) * 15;
      final dec = CelestialPositionService.parseDecDeg(obj.dec);
      final axes = SkyMapAngularSize.resolveArcmin(obj);
      final projected = SkyMapProjectionService.projectWithSize(
        raDeg: ra,
        decDeg: dec,
        centerRaDeg: _centerRaDeg,
        centerDecDeg: _centerDecDeg,
        canvasSize: _canvasSize,
        viewHeightDeg: _viewHeightDeg,
        majorArcmin: axes?.major,
        minorArcmin: axes?.minor,
      );

      final half = math.max(projected.renderWidth, projected.renderHeight) / 2;
      if (projected.screenX < -margin - half ||
          projected.screenY < -margin - half ||
          projected.screenX > _canvasSize.width + margin + half ||
          projected.screenY > _canvasSize.height + margin + half) {
        continue;
      }

      result.add(
        SkyMapRenderObject(
          catalogId: obj.id,
          name: obj.displayName,
          commonName: obj.commonName,
          objectType: obj.resolvedObjectType,
          catalog: obj.catalog,
          raDeg: ra,
          decDeg: dec,
          screenX: projected.screenX,
          screenY: projected.screenY,
          renderWidth: projected.renderWidth,
          renderHeight: projected.renderHeight,
          magnitude: double.tryParse(obj.magnitude),
          sizeMajorArcmin: axes?.major ?? obj.majorAxis,
          sizeMinorArcmin: axes?.minor ?? obj.minorAxis,
          positionAngleDeg: obj.positionAngle,
          raLabel: obj.ra,
          decLabel: obj.dec,
          captured: obj.captured,
          source: obj,
        ),
      );
    }

    if (result.length > 600 && _viewHeightDeg > 50) {
      result.sort((a, b) {
        final aPri = a.catalog == CatalogType.messier ? 0 : 1;
        final bPri = b.catalog == CatalogType.messier ? 0 : 1;
        final c = aPri.compareTo(bPri);
        if (c != 0) return c;
        final sizeA = (a.sizeMajorArcmin ?? 0);
        final sizeB = (b.sizeMajorArcmin ?? 0);
        return sizeB.compareTo(sizeA);
      });
      _visibleObjects = result.take(600).toList(growable: false);
    } else {
      _visibleObjects = result;
    }
  }

  void _rebuildStars() {
    if (!_filters.showBrightStars) {
      _visibleStars = const [];
      return;
    }

    const margin = 40.0;
    final result = <SkyMapStarRender>[];
    // 성도 전용 실좌표 항성 (별자리와 동일 카탈로그)
    for (final star in SkyMapConstellationCatalog.stars) {
      if (star.magnitude > SkyMapFilters.brightStarMagLimit) continue;

      final pixel = SkyMapProjectionService.project(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
        centerRaDeg: _centerRaDeg,
        centerDecDeg: _centerDecDeg,
        canvasSize: _canvasSize,
        viewHeightDeg: _viewHeightDeg,
      );
      if (pixel.dx < -margin ||
          pixel.dy < -margin ||
          pixel.dx > _canvasSize.width + margin ||
          pixel.dy > _canvasSize.height + margin) {
        continue;
      }

      result.add(
        SkyMapStarRender(
          id: star.id,
          name: SkyMapStarNamesKo.displayName(
            star.name,
            fallbackKo: star.nameKo,
          ),
          raDeg: star.raDeg,
          decDeg: star.decDeg,
          magnitude: star.magnitude,
          screenX: pixel.dx,
          screenY: pixel.dy,
          markerRadius: _starRadius(star.magnitude),
        ),
      );
    }
    _visibleStars = result;
  }

  void _rebuildConstellations() {
    if (!_filters.showConstellations) {
      _visibleConstellations = const [];
      return;
    }

    final result = <SkyMapConstellationRender>[];
    for (final figure in SkyMapConstellationCatalog.constellations) {
      final segments = <(SkyMapPoint, SkyMapPoint)>[];
      final labelPoints = <SkyMapPoint>[];

      for (final line in figure.lines) {
        final from = SkyMapConstellationCatalog.starsById[line.startStarId];
        final to = SkyMapConstellationCatalog.starsById[line.endStarId];
        if (from == null || to == null) continue;

        final a = SkyMapProjectionService.project(
          raDeg: from.raDeg,
          decDeg: from.decDeg,
          centerRaDeg: _centerRaDeg,
          centerDecDeg: _centerDecDeg,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        );
        final b = SkyMapProjectionService.project(
          raDeg: to.raDeg,
          decDeg: to.decDeg,
          centerRaDeg: _centerRaDeg,
          centerDecDeg: _centerDecDeg,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        );

        // RA 0/360 wrap 투영 아티팩트(화면을 가로지르는 가짜 직선) 제거
        if (!SkyMapProjectionService.shouldDrawConstellationSegment(
          raADeg: from.raDeg,
          decADeg: from.decDeg,
          raBDeg: to.raDeg,
          decBDeg: to.decDeg,
          projectedA: a,
          projectedB: b,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        )) {
          continue;
        }

        if (!_segmentNearView(a, b)) continue;

        segments.add((
          (x: a.dx, y: a.dy),
          (x: b.dx, y: b.dy),
        ));
        labelPoints.add((x: (a.dx + b.dx) / 2, y: (a.dy + b.dy) / 2));
      }

      if (segments.isEmpty) continue;
      var lx = 0.0;
      var ly = 0.0;
      for (final p in labelPoints) {
        lx += p.x;
        ly += p.y;
      }
      lx /= labelPoints.length;
      ly /= labelPoints.length;

      // ConstellationPainter.labelStyle 과 동일 규격 (히트 영역용)
      final labelPainter = TextPainter(
        text: TextSpan(
          text: figure.name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      result.add(
        SkyMapConstellationRender(
          id: figure.id,
          name: figure.name,
          segments: segments,
          labelX: lx,
          labelY: ly,
          labelWidth: labelPainter.width,
          labelHeight: labelPainter.height,
        ),
      );
    }
    _visibleConstellations = result;
  }

  bool _segmentNearView(Offset a, Offset b) {
    // 화면 밖 멀리 있는 선만 제외 — 가장자리는 표시해 전천 탐색 가능하게 함
    final bounds = Rect.fromLTWH(
      -canvasSize.width,
      -canvasSize.height,
      canvasSize.width * 3,
      canvasSize.height * 3,
    );
    return bounds.contains(a) ||
        bounds.contains(b) ||
        bounds.overlaps(Rect.fromPoints(a, b));
  }

  double _starRadius(double mag) {
    if (mag <= 0) return 5.5;
    if (mag <= 1) return 4.5;
    if (mag <= 2) return 3.5;
    return 2.8;
  }
}
