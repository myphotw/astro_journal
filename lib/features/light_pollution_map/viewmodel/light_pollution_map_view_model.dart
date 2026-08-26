import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/bortle_metadata.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/observation_condition.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/tonight_observation_session.dart';
import '../../../data/models/weather_data.dart';
import '../../../data/models/weather_forecast_slot.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/app_logger.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/light_pollution_tile_preload_service.dart';
import '../../../services/observation_condition_service.dart';
import '../../../services/observation_engine.dart';
import '../../../services/observation_score_service.dart';
import '../../../services/recommendation_engine.dart';
import '../../../services/recommendation_settings_service.dart';
import '../../../services/weather_service.dart';
import '../models/favorite_location_summary.dart';
import '../models/location_weather_info.dart';
import '../overlay/brightness_color_mapper.dart';
import '../overlay/favorite_marker_icon_builder.dart';
import '../overlay/light_pollution_tile_constants.dart';
import '../overlay/light_pollution_tile_provider.dart';

/// Default map center (Korea) when GPS is unavailable.

const kDefaultMapCenter = LatLng(37.5, 127.0);

const kLightPollutionTileOverlayId = TileOverlayId('light_pollution');

const _currentLocationMarkerId = MarkerId('current_location');

const _selectedLocationMarkerId = MarkerId('selected_location');

const _favoriteCoordinateTolerance = 0.0005;

class LightPollutionMapViewModel extends ChangeNotifier {
  LightPollutionMapViewModel(
    this._observationConditionService,
    this._geocodingService,
    this._tilePreloadService,
    this._weatherService,
    this._favoriteRepository,
    this._catalogRepository,
    this._equipmentRepository,
    this._observationEngine,
    this._recommendationEngine,
    this._equipmentRecommendationService,
    this._recommendationSettingsService,
  );

  static const _tag = 'LIGHT POLLUTION MAP';

  static const _searchDebounceDuration = Duration(milliseconds: 300);

  static const _minQueryLength = 2;

  final ObservationConditionService _observationConditionService;

  final GeocodingService _geocodingService;

  final LightPollutionTilePreloadService _tilePreloadService;

  final WeatherService _weatherService;
  final ObservationSiteRepository _favoriteRepository;
  final CatalogRepository _catalogRepository;
  final EquipmentRepository _equipmentRepository;
  final ObservationEngine _observationEngine;
  final RecommendationEngine _recommendationEngine;
  final EquipmentRecommendationService _equipmentRecommendationService;
  final RecommendationSettingsService _recommendationSettingsService;

  Timer? _searchDebounce;

  int _searchGeneration = 0;

  bool _isLoading = false;

  bool _isLoadingSelection = false;

  bool _isSearching = false;

  String? _errorMessage;

  String? _selectionErrorMessage;

  String? _searchErrorMessage;

  String? _selectedAddressLabel;

  List<LocationSearchSuggestion> _searchSuggestions = const [];

  ObservationCondition? _condition;

  ObservationCondition? _selectedCondition;

  LatLng? _selectedPosition;

  LatLng? _cameraFocus;

  LocationWeatherInfo? _weatherInfo;

  LocationWeatherInfo? _selectedWeatherInfo;

  bool _isLoadingWeather = false;

  bool _isLoadingSelectedWeather = false;

  String? _weatherErrorMessage;

  String? _selectedWeatherErrorMessage;

  List<ObservationSite> _favorites = const [];
  bool _isFavoritesDropdownOpen = false;
  List<FavoriteLocationSummary> _favoriteSummaries = const [];
  bool _isLoadingFavoriteSummaries = false;
  final Map<String, BitmapDescriptor> _favoriteMarkerIcons = {};
  bool _isBuildingFavoriteMarkerIcons = false;

  BortleMetadata? _metadata;

  LightPollutionTileProvider? _tileProvider;

  bool get isLoading => _isLoading;

  bool get isLoadingSelection => _isLoadingSelection;

  bool get isSearching => _isSearching;

  String? get errorMessage => _errorMessage;

  String? get selectionErrorMessage => _selectionErrorMessage;

  String? get searchErrorMessage => _searchErrorMessage;

  String? get selectedAddressLabel => _selectedAddressLabel;

  List<LocationSearchSuggestion> get searchSuggestions => _searchSuggestions;

  ObservationCondition? get condition => _condition;

  ObservationCondition? get selectedCondition => _selectedCondition;

  LatLng? get selectedPosition => _selectedPosition;

  LatLng? get cameraFocus => _cameraFocus;

  bool get hasSelection => _selectedPosition != null;

  LocationWeatherInfo? get weatherInfo => _weatherInfo;

  LocationWeatherInfo? get selectedWeatherInfo => _selectedWeatherInfo;

  bool get isLoadingWeather => _isLoadingWeather;

  bool get isLoadingSelectedWeather => _isLoadingSelectedWeather;

  String? get weatherErrorMessage => _weatherErrorMessage;

  String? get selectedWeatherErrorMessage => _selectedWeatherErrorMessage;

  List<ObservationSite> get favorites => _favorites;
  bool get isFavoritesDropdownOpen => _isFavoritesDropdownOpen;
  List<FavoriteLocationSummary> get favoriteSummaries => _favoriteSummaries;
  bool get isLoadingFavoriteSummaries => _isLoadingFavoriteSummaries;

  BortleMetadata? get metadata => _metadata;

  /// Overlay opacity (0.0–1.0). UI slider will bind here later.

  double get overlayOpacity => LightPollutionTileConstants.overlayOpacity;

  set overlayOpacity(double value) {
    final clamped = value.clamp(0.0, 1.0);

    if (LightPollutionTileConstants.overlayOpacity == clamped) return;

    LightPollutionTileConstants.overlayOpacity = clamped;

    _tileProvider?.clearCache();

    notifyListeners();
  }

  LightPollutionTileProvider? get tileProvider => _tileProvider;

  LatLng get mapCenter => _condition != null
      ? LatLng(_condition!.latitude, _condition!.longitude)
      : kDefaultMapCenter;

  Set<Marker> get markers {
    final markers = <Marker>{};

    if (_condition != null) {
      markers.add(
        Marker(
          markerId: _currentLocationMarkerId,

          position: LatLng(_condition!.latitude, _condition!.longitude),

          infoWindow: const InfoWindow(title: '현재 위치'),
        ),
      );
    }

    if (_selectedPosition != null) {
      markers.add(
        Marker(
          markerId: _selectedLocationMarkerId,

          position: _selectedPosition!,

          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),

          infoWindow: InfoWindow(
            title: _selectedAddressLabel?.trim().isNotEmpty == true
                ? _selectedAddressLabel!
                : '선택 위치',
            snippet: _selectedAddressLabel?.trim().isNotEmpty == true
                ? null
                : _selectedAddressLabel,
          ),
        ),
      );
    }

    for (final favorite in _favorites) {
      final icon =
          _favoriteMarkerIcons[_favoriteIconKey(favorite)] ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      markers.add(
        Marker(
          markerId: MarkerId(favorite.id),
          position: LatLng(favorite.latitude, favorite.longitude),
          icon: icon,
          infoWindow: InfoWindow(title: favorite.name),
          consumeTapEvents: true,
          onTap: () => selectFavorite(favorite),
        ),
      );
    }

    return markers;
  }

  Set<TileOverlay> get tileOverlays {
    final provider = _tileProvider;

    if (provider == null) return {};

    return {
      TileOverlay(
        tileOverlayId: kLightPollutionTileOverlayId,

        tileProvider: provider,

        transparency: 0.0,

        zIndex: 1,

        fadeIn: false,

        tileSize: LightPollutionTileConstants.tileSize,
      ),
    };
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();

    super.dispose();
  }

  bool _hasLoaded = false;
  bool get hasLoaded => _hasLoaded;

  /// 광해지도 첫 진입용 단계적 로드.
  ///
  /// 이전에는 GPS 고정 + Bortle DB 오픈 + 타일 프리로드를 한꺼번에 await해
  /// 탭 진입 시 앱이 멈춘 것처럼 보였다. 메타데이터/타일 준비 → 즐겨찾기 →
  /// GPS(타임아웃·캐시 위치) → 날씨/프리로드(지연) 순으로 나눈다.
  Future<void> load() async {
    if (_isLoading || _hasLoaded) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1) Bortle 메타데이터/타일 프로바이더를 먼저 준비해 지도를 바로 쓸 수 있게 한다.
      _metadata ??= await _observationConditionService.getMetadata();
      _ensureTileProvider();
      notifyListeners();

      // 2) 즐겨찾기는 GPS와 독립적으로 로드한다.
      await loadFavorites();

      // 3) GPS는 마지막 위치 우선 + 타임아웃으로 UI를 오래 막지 않는다.
      try {
        _condition = await _observationConditionService
            .getCurrentCondition(preferLastKnown: true)
            .timeout(const Duration(seconds: 12));
        _logConditionDebug(_condition!);
        _cameraFocus = LatLng(_condition!.latitude, _condition!.longitude);
      } catch (error) {
        _condition = null;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      }
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }

    // 4) 날씨만 백그라운드 로드. 타일 프리로드는 첫 진입 UI를 막지 않도록 생략한다.
    if (_condition != null) {
      unawaited(_loadCurrentWeather());
    }
  }

  /// Re-fetches GPS-based current location, light pollution, and weather.
  Future<void> refreshCurrentLocation() async {
    if (_isLoading) return;

    await _fetchCurrentCondition(preferLastKnown: false);

    if (_condition != null) {
      await _loadCurrentWeather();
    } else {
      _weatherInfo = null;
      _weatherErrorMessage = null;
      notifyListeners();
    }
  }

  Future<void> _fetchCurrentCondition({bool preferLastKnown = true}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _metadata ??= await _observationConditionService.getMetadata();
      _ensureTileProvider();

      _condition = await _observationConditionService
          .getCurrentCondition(preferLastKnown: preferLastKnown)
          .timeout(const Duration(seconds: 12));

      _logConditionDebug(_condition!);
      _cameraFocus = LatLng(_condition!.latitude, _condition!.longitude);
    } catch (error) {
      _condition = null;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectLocation(LatLng position, {String? addressLabel}) async {
    _selectedPosition = position;

    _selectedCondition = null;

    _selectedWeatherInfo = null;

    _selectionErrorMessage = null;

    _selectedWeatherErrorMessage = null;

    _selectedAddressLabel = addressLabel;

    _isLoadingSelection = true;

    _isLoadingSelectedWeather = true;

    notifyListeners();

    try {
      _selectedCondition = await _observationConditionService.getConditionAt(
        position.latitude,

        position.longitude,
      );
    } catch (error) {
      _selectedCondition = null;

      _selectionErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingSelection = false;

      notifyListeners();
    }

    unawaited(_loadSelectedWeather(position.latitude, position.longitude));

    if (addressLabel == null || addressLabel.trim().isEmpty) {
      unawaited(
        _resolveSelectedRegionName(position.latitude, position.longitude),
      );
    }
  }

  Future<void> _resolveSelectedRegionName(double lat, double lng) async {
    try {
      final result = await _geocodingService.getLocationInfo(lat, lng);
      final label = result?.regionName.trim();
      if (label == null || label.isEmpty) return;

      final selected = _selectedPosition;
      if (selected == null) return;
      if ((selected.latitude - lat).abs() > 0.00001 ||
          (selected.longitude - lng).abs() > 0.00001) {
        return;
      }

      _selectedAddressLabel = label;
      notifyListeners();
    } catch (_) {
      // 지역명 조회 실패 시 기본 "선택 위치" 유지.
    }
  }

  /// 입력 변경 시 디바운스 후 자동완성 제안을 불러온다.

  void onSearchQueryChanged(String query) {
    _searchDebounce?.cancel();

    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      _resetSearchState();

      notifyListeners();

      return;
    }

    closeFavoritesDropdown();

    if (trimmed.length < _minQueryLength) {
      _searchSuggestions = const [];

      _searchErrorMessage = null;

      _isSearching = false;

      notifyListeners();

      return;
    }

    _isSearching = true;

    _searchErrorMessage = null;

    notifyListeners();

    _searchDebounce = Timer(_searchDebounceDuration, () {
      unawaited(_fetchSuggestions(trimmed));
    });
  }

  /// Enter/검색 버튼 — 디바운스 없이 즉시 조회.

  Future<void> searchAddress(String query) async {
    _searchDebounce?.cancel();

    final trimmed = query.trim();

    if (trimmed.isEmpty) return;

    if (trimmed.length < _minQueryLength) {
      _searchSuggestions = const [];

      _searchErrorMessage = '두 글자 이상 입력해 주세요.';

      _isSearching = false;

      notifyListeners();

      return;
    }

    await _fetchSuggestions(trimmed);
  }

  Future<void> selectSearchSuggestion(
    LocationSearchSuggestion suggestion,
  ) async {
    _searchSuggestions = const [];

    _searchErrorMessage = null;

    _isSearching = true;

    notifyListeners();

    try {
      GeocodeForwardResult? result;
      if (suggestion.hasCoordinates) {
        result = GeocodeForwardResult(
          latitude: suggestion.latitude!,
          longitude: suggestion.longitude!,
          formattedAddress: suggestion.secondaryText ?? suggestion.mainText,
          placeName: suggestion.mainText,
        );
      } else if (suggestion.hasPlaceId) {
        result = await _geocodingService.getPlaceDetails(suggestion.placeId!);
      }

      if (result == null) {
        _searchErrorMessage = '장소 정보를 불러오지 못했습니다.';

        return;
      }

      await _applySearchResult(result);
    } catch (error) {
      _searchErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isSearching = false;

      notifyListeners();
    }
  }

  void clearSearchSuggestions() {
    _resetSearchState();

    notifyListeners();
  }

  Future<void> _fetchSuggestions(String query) async {
    final generation = ++_searchGeneration;

    try {
      if (generation != _searchGeneration) return;
      final suggestions = await _geocodingService.autocompleteLocations(query);

      if (generation != _searchGeneration) return;

      if (suggestions.isEmpty) {
        _searchSuggestions = const [];

        _searchErrorMessage = '검색 결과가 없습니다.';
      } else {
        _searchSuggestions = suggestions;

        _searchErrorMessage = null;
      }
    } catch (error) {
      if (generation != _searchGeneration) return;

      _searchSuggestions = const [];

      _searchErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;

        notifyListeners();
      }
    }
  }

  void _resetSearchState() {
    _searchGeneration++;

    _searchSuggestions = const [];

    _searchErrorMessage = null;

    _isSearching = false;
  }

  Future<void> _applySearchResult(GeocodeForwardResult result) async {
    _cameraFocus = LatLng(result.latitude, result.longitude);

    await selectLocation(_cameraFocus!, addressLabel: result.formattedAddress);
  }

  void clearCameraFocus() {
    if (_cameraFocus == null) return;

    _cameraFocus = null;

    notifyListeners();
  }

  void clearSelection() {
    _selectedPosition = null;

    _selectedCondition = null;

    _selectedWeatherInfo = null;

    _selectedAddressLabel = null;

    _selectionErrorMessage = null;

    _selectedWeatherErrorMessage = null;

    _resetSearchState();

    _isLoadingSelection = false;

    _isLoadingSelectedWeather = false;

    notifyListeners();
  }

  void onCameraIdle() {}

  void _ensureTileProvider() {
    final metadata = _metadata;

    if (metadata == null) return;

    if (_tileProvider == null) {
      _tileProvider = LightPollutionTileProvider(
        observationConditionService: _observationConditionService,

        metadata: metadata,
      );
      // 잘못 생성된 이전 타일(다른 알고리즘/캐시 키) 제거.
      _tileProvider!.clearCache();
    } else {
      _tileProvider!.updateMetadata(metadata);
    }
  }

  Future<void> _loadCurrentWeather() async {
    final condition = _condition;
    if (condition == null) return;

    _isLoadingWeather = true;
    _weatherErrorMessage = null;
    notifyListeners();

    try {
      _weatherInfo = await _fetchWeatherInfo(
        condition.latitude,
        condition.longitude,
      );
    } catch (error) {
      _weatherInfo = null;
      _weatherErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingWeather = false;
      notifyListeners();
    }
  }

  Future<void> _loadSelectedWeather(double latitude, double longitude) async {
    _isLoadingSelectedWeather = true;
    _selectedWeatherErrorMessage = null;
    notifyListeners();

    try {
      _selectedWeatherInfo = await _fetchWeatherInfo(latitude, longitude);
    } catch (error) {
      _selectedWeatherInfo = null;
      _selectedWeatherErrorMessage = error.toString().replaceFirst(
        'Exception: ',
        '',
      );
    } finally {
      _isLoadingSelectedWeather = false;
      notifyListeners();
    }
  }

  Future<LocationWeatherInfo> _fetchWeatherInfo(
    double latitude,
    double longitude,
  ) async {
    final results = await Future.wait([
      _weatherService.getCurrentWeather(latitude, longitude),
      _weatherService.getForecast(latitude, longitude),
    ]);

    return LocationWeatherInfo.buildWithEngine(
      observationEngine: _observationEngine,
      latitude: latitude,
      longitude: longitude,
      current: results[0] as WeatherData,
      forecasts: results[1] as List<WeatherForecastSlot>,
    );
  }

  void _logConditionDebug(ObservationCondition condition) {
    if (!kDebugMode) return;

    AppLogger.info(
      _tag,
      'lat=${condition.latitude} lng=${condition.longitude}',
    );

    AppLogger.info(_tag, 'Brightness : ${condition.brightness}');

    AppLogger.info(
      _tag,

      'ObservationScore : ${condition.observationScore?.round()}',
    );

    AppLogger.info(_tag, 'Row        : ${condition.row}');

    AppLogger.info(_tag, 'Col        : ${condition.col}');

    AppLogger.info(_tag, 'SQM        : ${condition.sqm}');

    AppLogger.info(_tag, 'Bortle     : ${condition.bortle}');
  }

  Future<void> loadFavorites() async {
    _favorites = (await _favoriteRepository.list())
        .where((site) => site.isFavorite)
        .toList();
    notifyListeners();
    unawaited(_ensureFavoriteMarkerIcons());
  }

  String _favoriteIconKey(ObservationSite favorite) =>
      '${favorite.id}::${favorite.name}';

  Future<void> _ensureFavoriteMarkerIcons() async {
    if (_isBuildingFavoriteMarkerIcons) return;

    final validKeys = _favorites.map(_favoriteIconKey).toSet();
    _favoriteMarkerIcons.removeWhere((key, _) => !validKeys.contains(key));

    final missing = _favorites
        .where((f) => !_favoriteMarkerIcons.containsKey(_favoriteIconKey(f)))
        .toList();
    if (missing.isEmpty) return;

    _isBuildingFavoriteMarkerIcons = true;
    try {
      for (final favorite in missing) {
        final icon = await FavoriteMarkerIconBuilder.build(favorite.name);
        _favoriteMarkerIcons[_favoriteIconKey(favorite)] = icon;
      }
      notifyListeners();
    } finally {
      _isBuildingFavoriteMarkerIcons = false;
    }
  }

  bool isFavorited(double latitude, double longitude) =>
      _findFavoriteAt(latitude, longitude) != null;

  ObservationSite? findFavoriteAt(double latitude, double longitude) =>
      _findFavoriteAt(latitude, longitude);

  String defaultFavoriteName({required bool isCurrent}) {
    if (isCurrent) return '현재 위치';
    final label = _selectedAddressLabel;
    if (label != null && label.trim().isNotEmpty) return label.trim();
    return '선택 위치';
  }

  Future<void> addFavorite({
    required String name,
    required double latitude,
    required double longitude,
    required ObservationCondition condition,
  }) async {
    final brightness = condition.brightness;
    final legendEntry = brightness != null
        ? BrightnessColorMapper.legendEntryFor(brightness)
        : null;

    final now = DateTime.now();
    final favorite = ObservationSite(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? '관측지' : name.trim(),
      latitude: latitude,
      longitude: longitude,
      bortle: condition.bortle,
      sqm: condition.sqm,
      brightnessGrade: legendEntry?.label,
      createdAt: now,
      updatedAt: now,
    );

    await _favoriteRepository.create(favorite);
    await loadFavorites();
  }

  Future<void> removeFavoriteAt(double latitude, double longitude) async {
    final existing = _findFavoriteAt(latitude, longitude);
    if (existing == null) return;
    await _favoriteRepository.delete(existing.id);
    await loadFavorites();
    if (_isFavoritesDropdownOpen) {
      await _loadFavoriteSummaries();
    }
  }

  Future<void> toggleFavoritesDropdown() async {
    _isFavoritesDropdownOpen = !_isFavoritesDropdownOpen;
    if (_isFavoritesDropdownOpen) {
      _resetSearchState();
      await _loadFavoriteSummaries();
    } else {
      _favoriteSummaries = const [];
    }
    notifyListeners();
  }

  void closeFavoritesDropdown() {
    if (!_isFavoritesDropdownOpen) return;
    _isFavoritesDropdownOpen = false;
    _favoriteSummaries = const [];
    notifyListeners();
  }

  Future<void> selectFavorite(ObservationSite favorite) async {
    _isFavoritesDropdownOpen = false;
    _favoriteSummaries = const [];
    notifyListeners();
    await selectLocation(
      LatLng(favorite.latitude, favorite.longitude),
      addressLabel: favorite.name,
    );
  }

  Future<void> _loadFavoriteSummaries() async {
    if (_favorites.isEmpty) {
      _favoriteSummaries = const [];
      _isLoadingFavoriteSummaries = false;
      return;
    }

    _isLoadingFavoriteSummaries = true;
    _favoriteSummaries = _favorites
        .map((f) => FavoriteLocationSummary(favorite: f, isLoading: true))
        .toList();
    notifyListeners();

    try {
      final catalog = await _catalogRepository.getAll();
      final equipment = await _equipmentRepository.getAll(activeOnly: true);
      final settings = await _recommendationSettingsService.load();

      final summaries = await Future.wait(
        _favorites.map(
          (favorite) => _buildFavoriteSummary(
            favorite,
            catalog: catalog,
            equipment: equipment,
            settings: settings,
          ),
        ),
      );

      if (!_isFavoritesDropdownOpen) return;
      _favoriteSummaries = summaries;
    } catch (_) {
      if (_isFavoritesDropdownOpen) {
        _favoriteSummaries = _favorites
            .map((f) => FavoriteLocationSummary(favorite: f))
            .toList();
      }
    } finally {
      _isLoadingFavoriteSummaries = false;
      notifyListeners();
    }
  }

  Future<FavoriteLocationSummary> _buildFavoriteSummary(
    ObservationSite favorite, {
    required List<CatalogObject> catalog,
    required List<Equipment> equipment,
    required RecommendationSettings settings,
  }) async {
    final now = DateTime.now();
    final weatherResults = await Future.wait([
      _weatherService.getCurrentWeather(favorite.latitude, favorite.longitude),
      _weatherService.getForecast(favorite.latitude, favorite.longitude),
    ]);
    final currentWeather = weatherResults[0] as WeatherData;
    final forecasts = weatherResults[1] as List<WeatherForecastSlot>;
    final weatherInfo = await LocationWeatherInfo.buildWithEngine(
      observationEngine: _observationEngine,
      latitude: favorite.latitude,
      longitude: favorite.longitude,
      current: currentWeather,
      forecasts: forecasts,
      now: now,
    );

    String? equipmentName;
    final targetNames = <String>[];

    try {
      final nightWindow = _estimateNightWindow(now);
      final session = TonightObservationSession(
        start: nightWindow.nightStart,
        end: nightWindow.nightEnd,
      );

      final context = await _observationEngine.buildContext(
        latitude: favorite.latitude,
        longitude: favorite.longitude,
        currentTime: now,
        weather: currentWeather,
        forecasts: forecasts,
        session: session,
        catalog: catalog,
      );

      final result = await _recommendationEngine.build(
        catalog: catalog,
        settings: settings,
        context: context,
        session: session,
        limit: 3,
        windSpeed: weatherInfo.windSpeed,
        referenceTime: now,
      );

      for (final rec in result.allRecommendations.take(3)) {
        targetNames.add(rec.object.displayName);
      }

      if (result.allRecommendations.isNotEmpty && equipment.isNotEmpty) {
        final topRec = result.allRecommendations.first;
        final todayRec = _equipmentRecommendationService.recommendForToday(
          object: topRec.object,
          equipment: equipment,
          recommendation: topRec,
          observerLatitude: favorite.latitude,
          observerLongitude: favorite.longitude,
        );
        equipmentName = todayRec.imaging?.equipment.name;
        if (equipmentName == null) {
          for (final visual in todayRec.visual) {
            if (visual.isRecommended && visual.isFeasibleToday) {
              equipmentName = visual.equipment.name;
              break;
            }
          }
        }
      }
    } catch (_) {
      // Weather-only summary is still useful when recommendation fails.
    }

    return FavoriteLocationSummary(
      favorite: favorite,
      weatherInfo: weatherInfo,
      recommendedEquipmentName: equipmentName,
      recommendedTargetNames: targetNames,
    );
  }

  ObservationSite? _findFavoriteAt(double latitude, double longitude) {
    for (final favorite in _favorites) {
      if ((favorite.latitude - latitude).abs() <=
              _favoriteCoordinateTolerance &&
          (favorite.longitude - longitude).abs() <=
              _favoriteCoordinateTolerance) {
        return favorite;
      }
    }
    return null;
  }

  static ({DateTime nightStart, DateTime nightEnd}) _estimateNightWindow(
    DateTime now,
  ) => ObservationScoreService.estimatedNightWindow(now);
}
