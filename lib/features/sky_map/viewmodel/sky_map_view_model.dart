import 'dart:async';
import 'dart:math' as math;

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
import '../../../data/models/site_horizon_profile.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/sky_map/sky_map_constellation_catalog.dart';
import '../../../data/sky_map/sky_map_star_names_ko.dart';
import '../../../services/celestial_position_service.dart';
import '../../../services/catalog_favorite_controller.dart';
import '../../../services/equipment/fov_framing_engine.dart';
import '../../../services/sky_map_angular_size.dart';
import '../../../services/sky_map_horizontal_projection_service.dart';
import '../../../services/sky_map_milky_way_service.dart';
import '../../../services/sky_map_night_timeline_service.dart';
import '../../../services/sky_map_projection_service.dart';
import '../../../services/sky_map_sun_position_service.dart';
import '../../../services/solar_system_ephemeris_service.dart';
import '../../observation_site/viewmodel/active_observation_site_view_model.dart';
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
    this.catalogs = const {CatalogType.messier},
    this.objectTypes = const {
      SkyMapObjectTypeFilter.galaxy,
      SkyMapObjectTypeFilter.openCluster,
      SkyMapObjectTypeFilter.globularCluster,
      SkyMapObjectTypeFilter.nebula,
      SkyMapObjectTypeFilter.planetaryNebula,
    },
    this.showConstellations = true,
    this.showBrightStars = true,
    this.showMilkyWay = true,
    this.showSolarSystem = true,
    this.showObservationSiteHorizon = true,
    this.favoritesOnly = false,
  });

  final Set<CatalogType> catalogs;
  final Set<SkyMapObjectTypeFilter> objectTypes;
  final bool showConstellations;
  final bool showBrightStars;
  final bool showMilkyWay;
  final bool showSolarSystem;
  final bool showObservationSiteHorizon;
  final bool favoritesOnly;

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
    bool? showMilkyWay,
    bool? showSolarSystem,
    bool? showObservationSiteHorizon,
    bool? favoritesOnly,
  }) {
    return SkyMapFilters(
      catalogs: catalogs ?? this.catalogs,
      objectTypes: objectTypes ?? this.objectTypes,
      showConstellations: showConstellations ?? this.showConstellations,
      showBrightStars: showBrightStars ?? this.showBrightStars,
      showMilkyWay: showMilkyWay ?? this.showMilkyWay,
      showSolarSystem: showSolarSystem ?? this.showSolarSystem,
      showObservationSiteHorizon:
          showObservationSiteHorizon ?? this.showObservationSiteHorizon,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
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
    this._equipmentRepository, [
    this._activeObservationSiteViewModel,
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now {
    _activeObservationSiteViewModel?.addListener(_handleObservationSiteChange);
    _observationTime = _roundedToMinute(_now());
    _observationDate = _nightTimelineService.observationDateFor(
      _observationTime,
    );
    _nightTimeline = _calculateNightTimeline(includeTime: _observationTime);
  }

  final CatalogRepository _catalogRepository;
  final EquipmentRepository _equipmentRepository;
  final ActiveObservationSiteViewModel? _activeObservationSiteViewModel;
  CatalogFavoriteController? _catalogFavorites;
  final DateTime Function() _now;
  final SkyMapMilkyWayService _milkyWayService = const SkyMapMilkyWayService();
  final SkyMapNightTimelineService _nightTimelineService =
      const SkyMapNightTimelineService();
  final SolarSystemEphemerisService _solarSystemEphemerisService =
      SolarSystemEphemerisService();

  static const double minViewHeightDeg =
      SkyMapHorizontalProjectionService.minViewHeightDeg;
  static const double maxViewHeightDeg =
      SkyMapHorizontalProjectionService.maxViewHeightDeg;
  // 일반 방향 시야의 초기 화면은 천정과 지평선 아래 일부를 함께 담되,
  // 중앙 방위각의 실제 지평선이 화면 하단 12.5% 지점에 오도록 한다.
  // 투영의 세로 각도/픽셀 비율을 사용하므로 화면 종횡비와 무관하다.
  static const double defaultHorizonScreenFraction = 0.875;
  static const double defaultViewHeightDeg = 120;
  static const double defaultCenterAzimuthDeg = 180;
  static const double defaultCenterAltitudeDeg =
      defaultViewHeightDeg * (defaultHorizonScreenFraction - 0.5);

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<CatalogObject> _deepSkyObjects = [];
  List<CatalogObject> _solarSystemObjects = [];
  List<CatalogObject> _constellationCatalogObjects = [];
  List<CatalogObject> _favoriteObjects = [];
  List<Equipment> _equipment = [];
  SkyMapFilters _filters = const SkyMapFilters();
  String _searchQuery = '';

  double _centerAzimuthDeg = defaultCenterAzimuthDeg;
  double _centerAltitudeDeg = defaultCenterAltitudeDeg;
  double _viewHeightDeg = defaultViewHeightDeg;
  Size _canvasSize = Size.zero;
  late DateTime _observationTime;
  late DateTime _observationDate;
  late SkyMapNightTimeline _nightTimeline;
  bool _isFollowingCurrentTime = true;
  double _sunAltitudeDeg = -90;
  double _sunAzimuthDeg = 0;
  Timer? _clockTimer;
  bool _observationRefreshScheduled = false;
  bool _disposed = false;

  final Map<String, AltAz> _catalogAltAz = {};
  final Map<String, SolarSystemPosition> _solarSystemPositions = {};
  final Map<String, AltAz> _starAltAz = {};
  SkyMapMilkyWayModel? _milkyWayModel;
  SkyMapMilkyWayHorizontalMesh _milkyWay =
      const SkyMapMilkyWayHorizontalMesh.empty();

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
  double get centerAzimuthDeg => _centerAzimuthDeg;
  double get centerAltitudeDeg => _centerAltitudeDeg;
  double get viewHeightDeg => _viewHeightDeg;
  DateTime get observationTime => _observationTime;
  DateTime get observationDate => _observationDate;
  SkyMapNightTimeline get nightTimeline => _nightTimeline;
  bool get isFollowingCurrentTime => _isFollowingCurrentTime;
  int get observationMinutes =>
      _observationTime.hour * 60 + _observationTime.minute;
  double get sunAltitudeDeg => _sunAltitudeDeg;
  double get sunAzimuthDeg => _sunAzimuthDeg;
  bool get hasObserverLocation =>
      _activeObservationSiteViewModel?.active.latitude != null &&
      _activeObservationSiteViewModel?.active.longitude != null;
  String get observerLabel =>
      _activeObservationSiteViewModel?.active.displayName ?? '위치 미설정';
  Size get canvasSize => _canvasSize;
  CatalogObject? get selectedObject => _selectedObject;
  FovPreview? get fovPreview => _fovPreview;
  bool get showFovOverlay => _showFovOverlay;
  List<SkyMapRenderObject> get visibleObjects =>
      List.unmodifiable(_visibleObjects);
  List<SkyMapStarRender> get visibleStars => List.unmodifiable(_visibleStars);
  List<SkyMapConstellationRender> get visibleConstellations =>
      List.unmodifiable(_visibleConstellations);
  List<CatalogObject> get solarSystemObjects =>
      List.unmodifiable(_solarSystemObjects);
  List<CatalogObject> get favoriteObjects =>
      List.unmodifiable(_favoriteObjects);
  Map<String, SolarSystemPosition> get solarSystemPositions =>
      Map.unmodifiable(_solarSystemPositions);
  SolarSystemPosition? solarSystemPositionFor(String catalogId) =>
      _solarSystemPositions[catalogId];
  SkyMapMilkyWayHorizontalMesh get milkyWay => _milkyWay;
  SiteHorizonProfile get observationSiteHorizonProfile =>
      _activeObservationSiteViewModel?.active.horizonProfile ??
      const SiteHorizonProfile();
  List<Equipment> get imagingEquipment =>
      _equipment.where((e) => e.isActive && e.hasFov).toList(growable: false);

  double get _observerLatitude =>
      _activeObservationSiteViewModel?.active.latitude ?? 0;
  double get _observerLongitude =>
      _activeObservationSiteViewModel?.active.longitude ?? 0;
  static DateTime _roundedToMinute(DateTime value) => value.isUtc
      ? DateTime.utc(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
        )
      : DateTime(value.year, value.month, value.day, value.hour, value.minute);

  void _handleObservationSiteChange() {
    _nightTimeline = _calculateNightTimeline(includeTime: _observationTime);
    _refreshHorizontalCoordinates();
    _rebuildVisible();
    notifyListeners();
  }

  void attachCatalogFavorites(CatalogFavoriteController controller) {
    if (identical(_catalogFavorites, controller)) return;
    _catalogFavorites?.removeListener(_handleCatalogFavoritesChange);
    _catalogFavorites = controller;
    _favoriteObjects = controller.favoriteObjects;
    controller.addListener(_handleCatalogFavoritesChange);
    if (_hasLoaded) {
      _refreshCatalogHorizontalCoordinates();
      _rebuildVisible();
      notifyListeners();
    }
  }

  void _handleCatalogFavoritesChange() {
    final controller = _catalogFavorites;
    if (controller == null) return;
    _favoriteObjects = controller.favoriteObjects;
    if (!_hasLoaded) return;
    _refreshCatalogHorizontalCoordinates();
    _rebuildVisible();
    notifyListeners();
  }

  void _startClock() {
    _clockTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_isFollowingCurrentTime) return;
      final next = _roundedToMinute(_now());
      if (next == _observationTime) return;
      _observationTime = next;
      final nextObservationDate = _nightTimelineService.observationDateFor(
        next,
      );
      if (nextObservationDate != _observationDate ||
          next.isBefore(_nightTimeline.start) ||
          next.isAfter(_nightTimeline.end)) {
        _observationDate = nextObservationDate;
        _nightTimeline = _calculateNightTimeline(includeTime: next);
      }
      _refreshHorizontalCoordinates();
      _rebuildVisible();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer?.cancel();
    _activeObservationSiteViewModel?.removeListener(
      _handleObservationSiteChange,
    );
    _catalogFavorites?.removeListener(_handleCatalogFavoritesChange);
    super.dispose();
  }

  /// 성도의 단일 관측 시각을 변경한다.
  ///
  /// UI는 시스템 로컬 wall-clock을 표시하고, 천문 계산 서비스가 내부에서
  /// UTC 절대 시각으로 변환한다. 수동 변경 뒤에는 매분 현재 시각을 따라가는
  /// 자동 시계를 멈춰 사용자가 고른 시각을 보존한다.
  void setObservationTime(DateTime value) {
    _setObservationTime(_roundedToMinute(value), followCurrent: false);
  }

  void setObservationDate(DateTime date) {
    final relativeMinutes = _observationTime
        .difference(_nightTimeline.midnight)
        .inMinutes;
    _observationDate = _dateOnlyLike(date, _observationTime.isUtc);
    _nightTimeline = _calculateNightTimeline();
    final next = _nightTimeline.midnight.add(
      Duration(minutes: relativeMinutes),
    );
    if (next.isBefore(_nightTimeline.start) ||
        next.isAfter(_nightTimeline.end)) {
      _nightTimeline = _calculateNightTimeline(includeTime: next);
    }
    _setObservationTime(next, followCurrent: false);
  }

  void setObservationTimelineMinutes(int minutes) {
    final next = _nightTimeline.timeAtOffset(minutes);
    _setObservationTime(next, followCurrent: false);
  }

  /// Slider drag 중의 연속 위치를 실제 관측 시각으로 반영한다.
  void setObservationTimelinePosition(double minutes) {
    final next = _nightTimeline.timeAtPosition(minutes);
    _setObservationTime(next, followCurrent: false);
  }

  /// Slider drag 종료 시 가장 가까운 10분 단위로 관측 시각을 확정한다.
  void finishObservationTimelinePosition(double minutes) {
    final snappedMinutes = ((minutes / 10).round() * 10)
        .clamp(0, _nightTimeline.totalMinutes)
        .toInt();
    setObservationTimelineMinutes(snappedMinutes);
  }

  void resetObservationTime() {
    final now = _roundedToMinute(_now());
    _observationDate = _nightTimelineService.observationDateFor(now);
    _nightTimeline = _calculateNightTimeline(includeTime: now);
    _setObservationTime(now, followCurrent: true);
  }

  SkyMapNightTimeline _calculateNightTimeline({DateTime? includeTime}) =>
      _nightTimelineService.calculate(
        observationDate: _observationDate,
        latitudeDeg: _observerLatitude,
        longitudeDeg: _observerLongitude,
        includeTime: includeTime,
      );

  static DateTime _dateOnlyLike(DateTime value, bool utc) => utc
      ? DateTime.utc(value.year, value.month, value.day)
      : DateTime(value.year, value.month, value.day);

  void _setObservationTime(DateTime next, {required bool followCurrent}) {
    if (next == _observationTime && followCurrent == _isFollowingCurrentTime) {
      return;
    }
    _observationTime = next;
    _isFollowingCurrentTime = followCurrent;
    // 날짜/시간 텍스트는 즉시 갱신하고, 연속 Slider 입력의 천문 계산은
    // 프레임당 한 번으로 합쳐 마지막 관측 시각만 반영한다.
    notifyListeners();
    _scheduleObservationRefresh();
  }

  void _scheduleObservationRefresh() {
    if (_observationRefreshScheduled) return;
    _observationRefreshScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _observationRefreshScheduled = false;
      if (_disposed) return;
      _refreshHorizontalCoordinates();
      _rebuildVisible();
      notifyListeners();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

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
    final target =
        _solarSystemPositions[selected.id]?.altAz ??
        _catalogAltAz[selected.id] ??
        _altAzForObject(selected);
    if (target == null) return const [];
    return SkyMapHorizontalProjectionService.projectFovCorners(
      objectAltitudeDeg: target.altitude,
      objectAzimuthDeg: target.azimuth,
      centerAltitudeDeg: _centerAltitudeDeg,
      centerAzimuthDeg: _centerAzimuthDeg,
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

      _solarSystemObjects = all
          .where(
            (object) =>
                object.catalog == CatalogType.solar &&
                SolarSystemBody.fromCatalogId(object.id) != null,
          )
          .toList(growable: false);

      _constellationCatalogObjects = all
          .where(
            (o) =>
                o.isPrimaryCatalog &&
                SkyMapFilters.constellationQueryCatalogs.contains(o.catalog),
          )
          .toList(growable: false);
      _favoriteObjects = _catalogFavorites?.favoriteObjects ?? const [];

      _equipment = await _equipmentRepository.getAll(activeOnly: true);
      try {
        _milkyWayModel = await _milkyWayService.load();
      } catch (_) {
        // 은하수 보조 자산이 누락돼도 기존 성도 탐색 기능은 계속 제공한다.
        _milkyWayModel = null;
      }
      _hasLoaded = true;
      _observationTime = _roundedToMinute(_now());
      _observationDate = _nightTimelineService.observationDateFor(
        _observationTime,
      );
      _nightTimeline = _calculateNightTimeline(includeTime: _observationTime);
      _refreshHorizontalCoordinates();
      _startClock();
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
    final favoriteModeChanged = _filters.favoritesOnly != filters.favoritesOnly;
    _filters = filters;
    if (favoriteModeChanged) _refreshCatalogHorizontalCoordinates();
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

  void setShowMilkyWay(bool value) {
    if (_filters.showMilkyWay == value) return;
    _filters = _filters.copyWith(showMilkyWay: value);
    _refreshMilkyWayCoordinates();
    notifyListeners();
  }

  void setShowSolarSystem(bool value) {
    setFilters(_filters.copyWith(showSolarSystem: value));
  }

  void setShowObservationSiteHorizon(bool value) {
    setFilters(_filters.copyWith(showObservationSiteHorizon: value));
  }

  void setFavoritesOnly(bool value) {
    setFilters(_filters.copyWith(favoritesOnly: value));
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

  bool _visibleRebuildScheduled = false;

  void panByPixels(Offset delta) {
    if (_canvasSize == Size.zero) return;
    final next = SkyMapHorizontalProjectionService.panCenter(
      delta: delta,
      centerAltitudeDeg: _centerAltitudeDeg,
      centerAzimuthDeg: _centerAzimuthDeg,
      canvasSize: _canvasSize,
      viewHeightDeg: _viewHeightDeg,
    );
    _centerAltitudeDeg = next.altitudeDeg;
    _centerAzimuthDeg = next.azimuthDeg;
    _scheduleVisibleRebuild();
  }

  void setViewHeightDeg(double degrees) {
    _viewHeightDeg = degrees.clamp(minViewHeightDeg, maxViewHeightDeg);
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
    _centerAzimuthDeg = defaultCenterAzimuthDeg;
    _centerAltitudeDeg = defaultCenterAltitudeDeg;
    _viewHeightDeg = defaultViewHeightDeg;
    _rebuildVisible();
    notifyListeners();
  }

  void selectObject(CatalogObject? object) {
    _selectedObject = object;
    if (object != null) {
      _ensureObjectVisibleInFilters(object);
      final target =
          _solarSystemPositions[object.id]?.altAz ??
          _catalogAltAz[object.id] ??
          _altAzForObject(object);
      if (target == null) {
        notifyListeners();
        return;
      }
      _centerAltitudeDeg = target.altitude;
      _centerAzimuthDeg = target.azimuth;
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
    var favoritesOnly = _filters.favoritesOnly;
    final visibleThroughFavorites =
        favoritesOnly && (_catalogFavorites?.isFavorite(object.id) ?? false);
    if (favoritesOnly && !visibleThroughFavorites) {
      favoritesOnly = false;
      changed = true;
    }
    var showSolarSystem = _filters.showSolarSystem;
    if (!visibleThroughFavorites &&
        object.catalog == CatalogType.solar &&
        !showSolarSystem) {
      showSolarSystem = true;
      changed = true;
    }
    final catalogs = Set<CatalogType>.from(_filters.catalogs);
    if (!visibleThroughFavorites &&
        SkyMapFilters.supportedCatalogs.contains(object.catalog) &&
        !catalogs.contains(object.catalog)) {
      catalogs.add(object.catalog);
      changed = true;
    }

    final objectTypes = Set<SkyMapObjectTypeFilter>.from(_filters.objectTypes);
    final needed = SkyMapObjectTypeFilter.forObjectType(
      object.resolvedObjectType,
    );
    if (!visibleThroughFavorites &&
        needed != null &&
        !objectTypes.contains(needed)) {
      objectTypes.add(needed);
      changed = true;
    }

    if (changed) {
      _filters = _filters.copyWith(
        catalogs: catalogs,
        objectTypes: objectTypes,
        showSolarSystem: showSolarSystem,
        favoritesOnly: favoritesOnly,
      );
    }
  }

  SkyMapRenderObject? hitTest(Offset position) {
    SkyMapRenderObject? best;
    var bestDist = double.infinity;
    for (final obj in _visibleObjects) {
      final dx = obj.screenX - position.dx;
      final dy = obj.screenY - position.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      final hitRadius = math.max(
        math.max(obj.renderWidth, obj.renderHeight) / 2,
        18,
      );
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
      if (c.showLabel && c.labelHitRect.contains(position)) return c;
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
        .where((o) => ConstellationNames.normalize(o.constellation) == target)
        .where((o) => catalogFilters.any((f) => f.matches(o)))
        .where((o) {
          final type = SkyMapObjectTypeFilter.forObjectType(
            o.resolvedObjectType,
          );
          // 범례에 없는 유형은 통과(희귀)
          if (type == null) return true;
          return typeFilters.contains(type);
        })
        .toList();
    list.sort((a, b) {
      final typeCmp = a.resolvedObjectType.label.compareTo(
        b.resolvedObjectType.label,
      );
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
    final isLandscapePreferred =
        coverage.bestAngleDegrees < 45 || coverage.bestAngleDegrees > 135;
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

    for (final obj in _solarSystemObjects) {
      final position = _solarSystemPositions[obj.id];
      if (position == null) continue;
      final hay = <String>[
        obj.displayName,
        obj.displayCommonName,
        obj.name,
        ...obj.displayAliases,
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) continue;
      results.add(
        SkyMapSearchResult(
          kind: SkyMapSearchKind.catalog,
          id: obj.id,
          title: obj.displayName,
          subtitle: '${obj.displayType} · 현재 관측 시각 위치',
          raDeg: position.raDeg,
          decDeg: position.decDeg,
          catalogObject: obj,
        ),
      );
      if (results.length >= 40) return results;
    }

    for (final figure in SkyMapConstellationCatalog.constellations) {
      final hay = '${figure.name} ${figure.nameEn} ${figure.id}'.toLowerCase();
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
      final raHours = CelestialPositionService.parseRaHours(obj.ra);
      final dec = CelestialPositionService.parseDecDeg(obj.dec);
      if (raHours == null || dec == null) continue;
      final ra = raHours * 15;
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
    final target = _altAzForEquatorial(raDeg: raDeg, decDeg: decDeg);
    _centerAltitudeDeg = target.altitude;
    _centerAzimuthDeg = target.azimuth;
    if (preferredViewHeightDeg != null) {
      _viewHeightDeg = preferredViewHeightDeg.clamp(
        minViewHeightDeg,
        maxViewHeightDeg,
      );
    } else if (_viewHeightDeg > 60) {
      _viewHeightDeg = 45;
    }
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

  AltAz _altAzForEquatorial({required double raDeg, required double decDeg}) =>
      CelestialPositionService.computeAltAz(
        raHours: raDeg / 15,
        decDeg: decDeg,
        latDeg: _observerLatitude,
        lonDeg: _observerLongitude,
        time: _observationTime,
      );

  AltAz? _altAzForObject(CatalogObject object) {
    final solarSystem = _solarSystemPositions[object.id];
    if (solarSystem != null) return solarSystem.altAz;
    final raHours = CelestialPositionService.parseRaHours(object.ra);
    final decDeg = CelestialPositionService.parseDecDeg(object.dec);
    if (raHours == null || decDeg == null) return null;
    return CelestialPositionService.computeAltAz(
      raHours: raHours,
      decDeg: decDeg,
      latDeg: _observerLatitude,
      lonDeg: _observerLongitude,
      time: _observationTime,
    );
  }

  void _refreshHorizontalCoordinates() {
    final sunPosition = SkyMapSunPositionService.position(
      time: _observationTime,
      latitudeDeg: _observerLatitude,
      longitudeDeg: _observerLongitude,
    );
    _sunAltitudeDeg = sunPosition.altitude;
    _sunAzimuthDeg = sunPosition.azimuth;
    _solarSystemPositions.clear();
    try {
      _solarSystemPositions.addEntries(
        _solarSystemEphemerisService
            .positions(
              time: _observationTime,
              latitudeDeg: _observerLatitude,
              longitudeDeg: _observerLongitude,
            )
            .map((position) => MapEntry(position.body.catalogId, position)),
      );
    } on RangeError {
      // 기존 성도 날짜 범위(1900~2200)는 유지한다. 천체력 계약 범위 밖에서는
      // 태양계 마커만 생략하고 별·심원천체·배경은 계속 표시한다.
    }
    _refreshMilkyWayCoordinates();
    _refreshCatalogHorizontalCoordinates();

    _starAltAz.clear();
    for (final star in SkyMapConstellationCatalog.stars) {
      _starAltAz[star.id] = _altAzForEquatorial(
        raDeg: star.raDeg,
        decDeg: star.decDeg,
      );
    }
  }

  void _refreshCatalogHorizontalCoordinates() {
    _catalogAltAz.clear();
    final objects = _filters.favoritesOnly
        ? _favoriteObjects.where(
            (object) => object.catalog != CatalogType.solar,
          )
        : _deepSkyObjects.where(_filters.matches);
    for (final object in objects) {
      final altAz = _altAzForObject(object);
      if (altAz != null) _catalogAltAz[object.id] = altAz;
    }
  }

  void _refreshMilkyWayCoordinates() {
    final milkyWayModel = _milkyWayModel;
    _milkyWay = _filters.showMilkyWay && milkyWayModel != null
        ? _milkyWayService.toHorizontal(
            model: milkyWayModel,
            time: _observationTime,
            latitudeDeg: _observerLatitude,
            longitudeDeg: _observerLongitude,
          )
        : const SkyMapMilkyWayHorizontalMesh.empty();
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

    final deepSkyCandidates = _filters.favoritesOnly
        ? _favoriteObjects.where(
            (object) => object.catalog != CatalogType.solar,
          )
        : _deepSkyObjects.where(_filters.matches);
    for (final obj in deepSkyCandidates) {
      if (query.isNotEmpty) {
        final hay = '${obj.displayName} ${obj.displayCommonName} ${obj.name}'
            .toLowerCase();
        if (!hay.contains(query)) continue;
      }

      final raHours = CelestialPositionService.parseRaHours(obj.ra);
      final dec = CelestialPositionService.parseDecDeg(obj.dec);
      if (raHours == null || dec == null) continue;
      final ra = raHours * 15;
      final altAz = _catalogAltAz[obj.id] ?? _altAzForObject(obj);
      if (altAz == null) continue;
      final axes = SkyMapAngularSize.resolveArcmin(obj);
      final projected = SkyMapHorizontalProjectionService.project(
        altitudeDeg: altAz.altitude,
        azimuthDeg: altAz.azimuth,
        centerAltitudeDeg: _centerAltitudeDeg,
        centerAzimuthDeg: _centerAzimuthDeg,
        canvasSize: _canvasSize,
        viewHeightDeg: _viewHeightDeg,
      );
      final rawMajor = axes?.major ?? 0;
      final rawMinor = axes?.minor ?? rawMajor;
      final major = math.max(
        rawMajor,
        SkyMapProjectionService.minDisplayArcmin,
      );
      final minor = math.max(
        rawMinor > 0 ? rawMinor : major,
        SkyMapProjectionService.minDisplayArcmin,
      );
      final projectedSize =
          SkyMapHorizontalProjectionService.projectAngularSize(
            majorArcmin: major,
            minorArcmin: minor,
            canvasSize: _canvasSize,
            viewHeightDeg: _viewHeightDeg,
          );

      final half = math.max(projectedSize.width, projectedSize.height) / 2;
      if (projected.pixel.dx < -margin - half ||
          projected.pixel.dy < -margin - half ||
          projected.pixel.dx > _canvasSize.width + margin + half ||
          projected.pixel.dy > _canvasSize.height + margin + half) {
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
          altitudeDeg: altAz.altitude,
          screenX: projected.pixel.dx,
          screenY: projected.pixel.dy,
          renderWidth: projectedSize.width,
          renderHeight: projectedSize.height,
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

    final favoriteIds = _catalogFavorites?.favoriteIds ?? const <String>{};
    if (_filters.showSolarSystem || _filters.favoritesOnly) {
      for (final obj in _solarSystemObjects) {
        if (_filters.favoritesOnly && !favoriteIds.contains(obj.id)) continue;
        final position = _solarSystemPositions[obj.id];
        if (position == null) continue;
        if (query.isNotEmpty) {
          final hay = <String>[
            obj.displayName,
            obj.displayCommonName,
            obj.name,
            ...obj.displayAliases,
          ].join(' ').toLowerCase();
          if (!hay.contains(query)) continue;
        }
        final projected = SkyMapHorizontalProjectionService.project(
          altitudeDeg: position.altAz.altitude,
          azimuthDeg: position.altAz.azimuth,
          centerAltitudeDeg: _centerAltitudeDeg,
          centerAzimuthDeg: _centerAzimuthDeg,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        );
        if (projected.pixel.dx < -margin ||
            projected.pixel.dy < -margin ||
            projected.pixel.dx > _canvasSize.width + margin ||
            projected.pixel.dy > _canvasSize.height + margin) {
          continue;
        }
        result.add(
          SkyMapRenderObject(
            catalogId: obj.id,
            name: obj.displayName,
            commonName: obj.commonName,
            objectType: obj.resolvedObjectType,
            catalog: obj.catalog,
            raDeg: position.raDeg,
            decDeg: position.decDeg,
            altitudeDeg: position.altAz.altitude,
            screenX: projected.pixel.dx,
            screenY: projected.pixel.dy,
            renderWidth: 18,
            renderHeight: 18,
            magnitude: double.tryParse(obj.magnitude),
            raLabel: _formatRa(position.raDeg),
            decLabel: _formatDec(position.decDeg),
            captured: obj.captured,
            source: obj,
          ),
        );
      }
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

      final altAz =
          _starAltAz[star.id] ??
          _altAzForEquatorial(raDeg: star.raDeg, decDeg: star.decDeg);
      final projected = SkyMapHorizontalProjectionService.project(
        altitudeDeg: altAz.altitude,
        azimuthDeg: altAz.azimuth,
        centerAltitudeDeg: _centerAltitudeDeg,
        centerAzimuthDeg: _centerAzimuthDeg,
        canvasSize: _canvasSize,
        viewHeightDeg: _viewHeightDeg,
      );
      final pixel = projected.pixel;
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
          altitudeDeg: altAz.altitude,
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
    final occupiedLabels = <Rect>[];
    for (final figure in SkyMapConstellationCatalog.constellations) {
      final segments = <(SkyMapPoint, SkyMapPoint)>[];
      final labelPoints = <SkyMapPoint>[];

      for (final line in figure.lines) {
        final from = SkyMapConstellationCatalog.starsById[line.startStarId];
        final to = SkyMapConstellationCatalog.starsById[line.endStarId];
        if (from == null || to == null) continue;
        final fromAltAz =
            _starAltAz[from.id] ??
            _altAzForEquatorial(raDeg: from.raDeg, decDeg: from.decDeg);
        final toAltAz =
            _starAltAz[to.id] ??
            _altAzForEquatorial(raDeg: to.raDeg, decDeg: to.decDeg);
        final a = SkyMapHorizontalProjectionService.project(
          altitudeDeg: fromAltAz.altitude,
          azimuthDeg: fromAltAz.azimuth,
          centerAltitudeDeg: _centerAltitudeDeg,
          centerAzimuthDeg: _centerAzimuthDeg,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        ).pixel;
        final b = SkyMapHorizontalProjectionService.project(
          altitudeDeg: toAltAz.altitude,
          azimuthDeg: toAltAz.azimuth,
          centerAltitudeDeg: _centerAltitudeDeg,
          centerAzimuthDeg: _centerAzimuthDeg,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        ).pixel;

        // 구면 각거리와 화면 chord를 함께 검사해 방위각 wrap 아티팩트를 제거한다.
        if (!SkyMapHorizontalProjectionService.shouldDrawConstellationSegment(
          altitudeADeg: fromAltAz.altitude,
          azimuthADeg: fromAltAz.azimuth,
          altitudeBDeg: toAltAz.altitude,
          azimuthBDeg: toAltAz.azimuth,
          projectedA: a,
          projectedB: b,
          canvasSize: _canvasSize,
          viewHeightDeg: _viewHeightDeg,
        )) {
          continue;
        }

        if (!_segmentNearView(a, b)) continue;

        segments.add((
          (x: a.dx, y: a.dy, altitudeDeg: fromAltAz.altitude),
          (x: b.dx, y: b.dy, altitudeDeg: toAltAz.altitude),
        ));
        labelPoints.add((
          x: (a.dx + b.dx) / 2,
          y: (a.dy + b.dy) / 2,
          altitudeDeg: (fromAltAz.altitude + toAltAz.altitude) / 2,
        ));
      }

      if (segments.isEmpty) continue;
      var lx = 0.0;
      var ly = 0.0;
      var labelAltitude = 0.0;
      for (final p in labelPoints) {
        lx += p.x;
        ly += p.y;
        labelAltitude += p.altitudeDeg;
      }
      lx /= labelPoints.length;
      ly /= labelPoints.length;
      labelAltitude /= labelPoints.length;

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

      final labelBounds = Rect.fromCenter(
        center: Offset(lx, ly),
        width: labelPainter.width + 20,
        height: labelPainter.height + 16,
      );
      final showLabel =
          (Offset.zero & _canvasSize).overlaps(labelBounds) &&
          !occupiedLabels.any((bounds) => bounds.overlaps(labelBounds));
      if (showLabel) occupiedLabels.add(labelBounds);

      result.add(
        SkyMapConstellationRender(
          id: figure.id,
          name: figure.name,
          segments: segments,
          labelX: lx,
          labelY: ly,
          labelWidth: labelPainter.width,
          labelHeight: labelPainter.height,
          labelAltitudeDeg: labelAltitude,
          showLabel: showLabel,
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
    if (mag <= 0) return 3.4;
    if (mag <= 1) return 2.8;
    if (mag <= 2) return 2.1;
    return 1.55;
  }

  static String _formatRa(double raDeg) {
    final totalSeconds = (raDeg / 15 * 3600).round() % (24 * 3600);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}h '
        '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }

  static String _formatDec(double decDeg) {
    final sign = decDeg < 0 ? '-' : '+';
    final totalSeconds = (decDeg.abs() * 3600).round();
    final degrees = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '$sign${degrees.toString().padLeft(2, '0')}° '
        '${minutes.toString().padLeft(2, '0')}′ '
        '${seconds.toString().padLeft(2, '0')}″';
  }
}
