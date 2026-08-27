import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/google_map_dark_style.dart';
import '../../../core/services/performance_probe.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_condition.dart';
import '../../../data/models/observation_site.dart';
import '../../../shared/widgets/google_map_gate.dart';
import '../viewmodel/light_pollution_map_view_model.dart';
import '../widgets/light_pollution_legend.dart';
import '../widgets/light_pollution_favorite_name_dialog.dart';
import '../widgets/light_pollution_location_card.dart';
import '../widgets/light_pollution_map_search_bar.dart';

class LightPollutionMapScreen extends StatefulWidget {
  const LightPollutionMapScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<LightPollutionMapScreen> createState() =>
      _LightPollutionMapScreenState();
}

class _LightPollutionMapScreenState extends State<LightPollutionMapScreen> {
  GoogleMapController? _mapController;
  bool _didInitialCameraMove = false;

  /// 광해 타일 기본 ON (필터 레이어 표시).
  bool _showTileOverlay = true;
  LatLng? _lastCameraFocus;
  bool _mapMounted = false;
  bool _favoriteMutationInProgress = false;

  static const _initialZoom = 11.0;
  static const _locationCardWidth = 188.0;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _mapMounted = true;
  }

  @override
  void didUpdateWidget(covariant LightPollutionMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      if (!_mapMounted) {
        setState(() => _mapMounted = true);
      }
      _maybeMoveToInitialPosition(force: true);
      context.read<LightPollutionMapViewModel>().loadFavorites();
    }
  }

  @override
  void dispose() {
    _mapController = null;
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _maybeMoveToInitialPosition(force: true);
  }

  void _onMapTap(LatLng position) {
    if (!widget.isActive) return;
    context.read<LightPollutionMapViewModel>().selectLocation(position);
  }

  void _maybeMoveToInitialPosition({bool force = false}) {
    final vm = context.read<LightPollutionMapViewModel>();
    if (_mapController == null || vm.condition == null) return;
    if (_didInitialCameraMove && !force) return;

    _didInitialCameraMove = true;
    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(vm.mapCenter, _initialZoom),
      );
    } catch (_) {}
  }

  void _maybeFocusCamera(LightPollutionMapViewModel vm) {
    final focus = vm.cameraFocus;
    if (focus == null) return;

    if (_mapController == null) {
      vm.clearCameraFocus();
      return;
    }
    if (focus == _lastCameraFocus) {
      vm.clearCameraFocus();
      return;
    }

    _lastCameraFocus = focus;
    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(focus, _initialZoom),
      );
    } catch (_) {}
    vm.clearCameraFocus();
  }

  Future<void> _goToCurrentLocation(LightPollutionMapViewModel vm) async {
    await vm.refreshCurrentLocation();
    if (!mounted || _mapController == null || vm.condition == null) return;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(vm.condition!.latitude, vm.condition!.longitude),
        _initialZoom,
      ),
    );
  }

  String? _selectedSubtitle(LightPollutionMapViewModel vm) {
    return _formatLatLng(vm.selectedPosition);
  }

  String _selectedTitle(LightPollutionMapViewModel vm) {
    final label = vm.selectedAddressLabel;
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    return '선택 위치';
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

  Future<void> _goToFavoriteLocation(
    LightPollutionMapViewModel vm,
    ObservationSite favorite,
  ) async {
    final position = LatLng(favorite.latitude, favorite.longitude);

    vm.closeFavoritesDropdown();

    if (_mapController != null) {
      _lastCameraFocus = position;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(position, _initialZoom),
      );
    }

    await vm.selectLocation(position, addressLabel: favorite.name);
  }

  Future<String?> _showAddFavoriteNameDialog(String defaultName) async {
    return showDialog<String>(
      context: context,
      builder: (_) => LightPollutionFavoriteNameDialog(
        defaultName: defaultName,
      ),
    );
  }

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

  void _toggleTileOverlay(LightPollutionMapViewModel vm) {
    if (vm.metadata == null || _mapController == null) return;
    setState(() => _showTileOverlay = !_showTileOverlay);
  }

  @override
  Widget build(BuildContext context) {
    PerformanceProbe.event(
      'widget.light_pollution_map.build',
      state: 'active=${widget.isActive} mounted=$_mapMounted',
    );
    final vm = context.watch<LightPollutionMapViewModel>();

    if (widget.isActive &&
        !_didInitialCameraMove &&
        !vm.isLoading &&
        vm.condition != null &&
        _mapController != null) {
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
          if (_mapMounted && vm.metadata != null)
            IconButton(
              tooltip: _showTileOverlay ? '광해 레이어 끄기' : '광해 레이어 켜기',
              onPressed: () => _toggleTileOverlay(vm),
              icon: Icon(
                _showTileOverlay ? Icons.layers : Icons.layers_outlined,
                color: _showTileOverlay ? AppColors.solar : null,
              ),
            ),
        ],
      ),
      body: !_mapMounted
          ? const Center(
              child: Text(
                '지도를 불러오는 중…',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          : GoogleMapGate(
              builder: (context) => Stack(
                children: [
                  Positioned.fill(
                    child: GoogleMap(
                      style: GoogleMapDarkStyle.json,
                      mapType: MapType.normal,
                      initialCameraPosition: CameraPosition(
                        target: vm.mapCenter,
                        zoom: _initialZoom,
                      ),
                      markers: widget.isActive ? vm.markers : const {},
                      tileOverlays: widget.isActive && _showTileOverlay
                          ? vm.tileOverlays
                          : const {},
                      onMapCreated: _onMapCreated,
                      onTap: _onMapTap,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      compassEnabled: true,
                      mapToolbarEnabled: false,
                      liteModeEnabled: false,
                    ),
                  ),
                  // 오버레이는 Positioned만 사용 — expand Stack이 터치를 가로채지 않게 한다.
                  if (widget.isActive) ...[
                    Positioned(
                      left: AppTheme.spacingMd,
                      right: AppTheme.spacingMd,
                      top:
                          MediaQuery.paddingOf(context).top +
                          AppTheme.spacingSm,
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
                      bottom:
                          MediaQuery.paddingOf(context).bottom +
                          AppTheme.spacingMd,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vm.hasSelection) ...[
                            LightPollutionLocationCard(
                              width: _locationCardWidth,
                              title: _selectedTitle(vm),
                              subtitle: _selectedSubtitle(vm),
                              condition: vm.selectedCondition,
                              isLoading: vm.isLoadingSelection,
                              errorMessage: vm.selectionErrorMessage,
                              weatherInfo: vm.selectedWeatherInfo,
                              isLoadingWeather: vm.isLoadingSelectedWeather,
                              weatherErrorMessage:
                                  vm.selectedWeatherErrorMessage,
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
                            onFavoriteTap: vm.condition != null
                                ? () => _handleFavoriteTap(
                                    vm: vm,
                                    latitude: vm.condition!.latitude,
                                    longitude: vm.condition!.longitude,
                                    condition: vm.condition,
                                    isCurrent: true,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: AppTheme.spacingMd,
                      bottom:
                          MediaQuery.paddingOf(context).bottom +
                          AppTheme.spacingMd,
                      child: const LightPollutionLegend(),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  static String _formatLatLng(LatLng? position) {
    if (position == null) return '';
    return '${position.latitude.toStringAsFixed(4)}, '
        '${position.longitude.toStringAsFixed(4)}';
  }
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
