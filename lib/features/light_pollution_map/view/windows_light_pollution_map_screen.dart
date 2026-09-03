import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps;
import 'package:latlong2/latlong.dart' as lat_lng;
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_condition.dart';
import '../../../data/models/observation_site.dart';
import '../overlay/light_pollution_tile_constants.dart';
import '../overlay/windows_light_pollution_tile_provider.dart';
import '../viewmodel/light_pollution_map_view_model.dart';
import '../widgets/light_pollution_favorite_name_dialog.dart';
import '../widgets/light_pollution_legend.dart';
import '../widgets/light_pollution_location_card.dart';
import '../widgets/light_pollution_map_search_bar.dart';

/// Windows-only map surface.
///
/// Google Maps Flutter has no Windows implementation. This view keeps the
/// current light-pollution data, selection, favourite and location-card
/// contracts while rendering the basemap with a pure Flutter map widget.
class WindowsLightPollutionMapScreen extends StatefulWidget {
  const WindowsLightPollutionMapScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<WindowsLightPollutionMapScreen> createState() =>
      _WindowsLightPollutionMapScreenState();
}

class _WindowsLightPollutionMapScreenState
    extends State<WindowsLightPollutionMapScreen> {
  static const _initialZoom = 11.0;
  static const _locationCardWidth = 220.0;

  final _mapController = flutter_map.MapController();
  bool _isMapReady = false;
  bool _didInitialCameraMove = false;
  bool _showTileOverlay = true;
  google_maps.LatLng? _lastCameraFocus;
  bool _favoriteMutationInProgress = false;

  @override
  void didUpdateWidget(covariant WindowsLightPollutionMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _maybeMoveToInitialPosition(force: true);
      context.read<LightPollutionMapViewModel>().loadFavorites();
    }
  }

  void _onMapReady() {
    _isMapReady = true;
    _maybeMoveToInitialPosition(force: true);
  }

  void _onMapTap(lat_lng.LatLng point) {
    if (!widget.isActive) return;
    context.read<LightPollutionMapViewModel>().selectLocation(
      google_maps.LatLng(point.latitude, point.longitude),
    );
  }

  void _maybeMoveToInitialPosition({bool force = false}) {
    if (!_isMapReady) return;
    final vm = context.read<LightPollutionMapViewModel>();
    if (vm.condition == null || (_didInitialCameraMove && !force)) return;

    _didInitialCameraMove = true;
    _mapController.move(_toMapLatLng(vm.mapCenter), _initialZoom);
  }

  void _maybeFocusCamera(LightPollutionMapViewModel vm) {
    final focus = vm.cameraFocus;
    if (focus == null) return;
    if (!_isMapReady || focus == _lastCameraFocus) {
      vm.clearCameraFocus();
      return;
    }

    _lastCameraFocus = focus;
    _mapController.move(_toMapLatLng(focus), _initialZoom);
    vm.clearCameraFocus();
  }

  Future<void> _goToCurrentLocation(LightPollutionMapViewModel vm) async {
    await vm.refreshCurrentLocation();
    if (!mounted || vm.condition == null) return;
    _mapController.move(_conditionPoint(vm.condition!), _initialZoom);
  }

  Future<void> _goToFavoriteLocation(
    LightPollutionMapViewModel vm,
    ObservationSite favorite,
  ) async {
    final position = google_maps.LatLng(favorite.latitude, favorite.longitude);
    vm.closeFavoritesDropdown();
    _lastCameraFocus = position;
    if (_isMapReady) _mapController.move(_toMapLatLng(position), _initialZoom);
    await vm.selectLocation(position, addressLabel: favorite.name);
  }

  Future<void> _handleFavoriteTap({
    required LightPollutionMapViewModel vm,
    required double latitude,
    required double longitude,
    required ObservationCondition? condition,
    required bool isCurrent,
  }) async {
    if (condition == null || _favoriteMutationInProgress) return;
    _favoriteMutationInProgress = true;
    try {
      if (vm.isFavorited(latitude, longitude)) {
        final confirmed = await _confirmDeleteFavorite();
        if (!confirmed || !mounted) return;
        await vm.removeFavoriteAt(latitude, longitude);
        return;
      }

      final name = await _showAddFavoriteNameDialog(
        vm.defaultFavoriteName(isCurrent: isCurrent),
      );
      if (!mounted || name == null) return;
      await vm.addFavorite(
        name: name,
        latitude: latitude,
        longitude: longitude,
        condition: condition,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기를 저장하지 못했습니다.')),
        );
      }
    } finally {
      _favoriteMutationInProgress = false;
    }
  }

  Future<String?> _showAddFavoriteNameDialog(String defaultName) =>
      showDialog<String>(
        context: context,
        builder: (_) => LightPollutionFavoriteNameDialog(
          defaultName: defaultName,
        ),
      );

  Future<bool> _confirmDeleteFavorite() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: const Text('즐겨찾기를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LightPollutionMapViewModel>();
    if (widget.isActive &&
        !_didInitialCameraMove &&
        !vm.isLoading &&
        vm.condition != null &&
        _isMapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeMoveToInitialPosition();
      });
    }
    if (widget.isActive && vm.cameraFocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFocusCamera(vm);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('광해지도'),
        actions: [
          if (vm.metadata != null)
            IconButton(
              tooltip: _showTileOverlay ? '광해 레이어 끄기' : '광해 레이어 켜기',
              onPressed: () => setState(
                () => _showTileOverlay = !_showTileOverlay,
              ),
              icon: Icon(
                _showTileOverlay ? Icons.layers : Icons.layers_outlined,
                color: _showTileOverlay ? AppColors.solar : null,
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: flutter_map.FlutterMap(
              mapController: _mapController,
              options: flutter_map.MapOptions(
                initialCenter: _toMapLatLng(vm.mapCenter),
                initialZoom: _initialZoom,
                onMapReady: _onMapReady,
                onTap: (_, point) => _onMapTap(point),
              ),
              children: [
                flutter_map.TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.astro_journal',
                ),
                if (widget.isActive && _showTileOverlay && vm.metadata != null)
                  flutter_map.TileLayer(
                    urlTemplate: 'bortle://{z}/{x}/{y}.png',
                    tileProvider: WindowsLightPollutionTileProvider(
                      loadTileBytes: vm.getLightPollutionTileBytes,
                    ),
                    maxNativeZoom: 19,
                    opacity: LightPollutionTileConstants.overlayOpacity,
                  ),
                if (widget.isActive)
                  flutter_map.MarkerLayer(markers: _markers(vm)),
              ],
            ),
          ),
          const Positioned(
            right: AppTheme.spacingSm,
            bottom: AppTheme.spacingSm,
            child: _OpenStreetMapAttribution(),
          ),
          if (widget.isActive) ...[
            Positioned(
              left: AppTheme.spacingMd,
              top: AppTheme.spacingMd,
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LightPollutionMapSearchBar(
                    onFavoriteSelected: (favorite) =>
                        _goToFavoriteLocation(vm, favorite),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  _MapMyLocationButton(
                    enabled: !vm.isLoading,
                    onPressed: () => _goToCurrentLocation(vm),
                  ),
                ],
              ),
            ),
            Positioned(
              left: AppTheme.spacingMd,
              bottom: AppTheme.spacingMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.hasSelection) ...[
                    LightPollutionLocationCard(
                      width: _locationCardWidth,
                      title: _selectedTitle(vm),
                      subtitle: _formatLatLng(vm.selectedPosition),
                      condition: vm.selectedCondition,
                      isLoading: vm.isLoadingSelection,
                      errorMessage: vm.selectionErrorMessage,
                      weatherInfo: vm.selectedWeatherInfo,
                      isLoadingWeather: vm.isLoadingSelectedWeather,
                      weatherErrorMessage: vm.selectedWeatherErrorMessage,
                      isFavorited:
                          vm.selectedPosition != null &&
                          vm.selectedCondition != null &&
                          vm.isFavorited(
                            vm.selectedPosition!.latitude,
                            vm.selectedPosition!.longitude,
                          ),
                      onFavoriteTap:
                          vm.selectedPosition != null &&
                              vm.selectedCondition != null
                          ? () => _handleFavoriteTap(
                              vm: vm,
                              latitude: vm.selectedPosition!.latitude,
                              longitude: vm.selectedPosition!.longitude,
                              condition: vm.selectedCondition,
                              isCurrent: false,
                            )
                          : null,
                      onClose: vm.clearSelection,
                    ),
                    const SizedBox(height: AppTheme.spacingSm),
                  ],
                  LightPollutionLocationCard(
                    width: _locationCardWidth,
                    title: '현재 위치',
                    condition: vm.condition,
                    isLoading: vm.isLoading,
                    errorMessage: vm.errorMessage,
                    weatherInfo: vm.weatherInfo,
                    isLoadingWeather: vm.isLoadingWeather,
                    weatherErrorMessage: vm.weatherErrorMessage,
                    isFavorited:
                        vm.condition != null &&
                        vm.isFavorited(
                          vm.condition!.latitude,
                          vm.condition!.longitude,
                        ),
                    onFavoriteTap: vm.condition == null
                        ? null
                        : () => _handleFavoriteTap(
                            vm: vm,
                            latitude: vm.condition!.latitude,
                            longitude: vm.condition!.longitude,
                            condition: vm.condition,
                            isCurrent: true,
                          ),
                  ),
                ],
              ),
            ),
            const Positioned(
              right: AppTheme.spacingMd,
              bottom: AppTheme.spacingMd,
              child: LightPollutionLegend(),
            ),
          ],
        ],
      ),
    );
  }

  List<flutter_map.Marker> _markers(LightPollutionMapViewModel vm) {
    final markers = <flutter_map.Marker>[];
    if (vm.condition != null) {
      markers.add(
        _marker(
          point: _conditionPoint(vm.condition!),
          icon: Icons.my_location,
          color: AppColors.solar,
          tooltip: '현재 위치',
        ),
      );
    }
    if (vm.selectedPosition != null) {
      markers.add(
        _marker(
          point: _toMapLatLng(vm.selectedPosition!),
          icon: Icons.place,
          color: Colors.lightBlueAccent,
          tooltip: _selectedTitle(vm),
        ),
      );
    }
    for (final favorite in vm.favorites) {
      markers.add(
        _marker(
          point: lat_lng.LatLng(favorite.latitude, favorite.longitude),
          icon: Icons.star,
          color: Colors.amber,
          tooltip: favorite.name,
          onTap: () => _goToFavoriteLocation(vm, favorite),
        ),
      );
    }
    return markers;
  }

  flutter_map.Marker _marker({
    required lat_lng.LatLng point,
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
  }) => flutter_map.Marker(
    point: point,
    width: 44,
    height: 44,
    child: Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: color, size: 30, shadows: const [
          Shadow(color: Colors.black54, blurRadius: 4),
        ]),
      ),
    ),
  );

  String _selectedTitle(LightPollutionMapViewModel vm) {
    final label = vm.selectedAddressLabel;
    return label == null || label.trim().isEmpty ? '선택 위치' : label.trim();
  }

  static String _formatLatLng(google_maps.LatLng? position) {
    if (position == null) return '';
    return '${position.latitude.toStringAsFixed(4)}, '
        '${position.longitude.toStringAsFixed(4)}';
  }

  static lat_lng.LatLng _conditionPoint(ObservationCondition condition) =>
      lat_lng.LatLng(condition.latitude, condition.longitude);

  static lat_lng.LatLng _toMapLatLng(google_maps.LatLng point) =>
      lat_lng.LatLng(point.latitude, point.longitude);
}

class _MapMyLocationButton extends StatelessWidget {
  const _MapMyLocationButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: surface.withValues(alpha: 0.94),
      elevation: 3,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.my_location,
            size: 22,
            color: enabled ? AppColors.solar : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _OpenStreetMapAttribution extends StatelessWidget {
  const _OpenStreetMapAttribution();

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.58),
    borderRadius: BorderRadius.circular(4),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Text(
        '© OpenStreetMap contributors',
        style: TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ),
  );
}
