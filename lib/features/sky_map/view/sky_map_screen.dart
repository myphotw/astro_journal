import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/sky_map_render_object.dart';
import '../viewmodel/sky_map_view_model.dart';
import '../widgets/painters/sky_map_composite_painter.dart';
import '../widgets/sky_map_constellation_objects_sheet.dart';
import '../widgets/sky_map_filter_sheet.dart';
import '../widgets/sky_map_object_detail_sheet.dart';
import '../widgets/sky_map_object_symbol.dart';

/// Catalog 기반 성도 / Target Planner.
class SkyMapScreen extends StatefulWidget {
  const SkyMapScreen({super.key});

  @override
  State<SkyMapScreen> createState() => _SkyMapScreenState();
}

class _SkyMapScreenState extends State<SkyMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _showSearchResults = false;

  /// 터치/마우스 포인터별 마지막 local 위치 (ScaleGesture 미사용).
  final Map<int, Offset> _pointerPositions = {};
  double? _pinchStartDistance;
  double? _pinchStartViewHeight;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool _isDragPointer(PointerEvent event) {
    return event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.mouse;
  }

  void _clearPinch() {
    _pinchStartDistance = null;
    _pinchStartViewHeight = null;
  }

  void _onPointerDown(PointerDownEvent event, SkyMapViewModel vm) {
    if (!_isDragPointer(event)) return;
    _pointerPositions[event.pointer] = event.localPosition;
    if (_pointerPositions.length == 2) {
      final pts = _pointerPositions.values.toList(growable: false);
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartViewHeight = vm.viewHeightDeg;
    } else {
      _clearPinch();
    }
  }

  void _onPointerMove(PointerMoveEvent event, SkyMapViewModel vm) {
    if (!_pointerPositions.containsKey(event.pointer)) return;
    final previous = _pointerPositions[event.pointer]!;
    _pointerPositions[event.pointer] = event.localPosition;

    if (_pointerPositions.length >= 2 &&
        _pinchStartDistance != null &&
        _pinchStartViewHeight != null &&
        _pinchStartDistance! > 1) {
      // 실제 두 손가락 핀치만 zoom
      final pts = _pointerPositions.values.toList(growable: false);
      final dist = (pts[0] - pts[1]).distance;
      if (dist > 1) {
        vm.setViewHeightDeg(
          _pinchStartViewHeight! * _pinchStartDistance! / dist,
        );
      }
      return;
    }

    // 한 포인터: pan만 (scale 절대 사용 안 함)
    final delta = event.localPosition - previous;
    if (delta.dx != 0 || delta.dy != 0) {
      vm.panByPixels(delta);
    }
  }

  void _onPointerUpOrCancel(int pointer) {
    _pointerPositions.remove(pointer);
    if (_pointerPositions.length < 2) {
      _clearPinch();
    }
  }

  Future<void> _openDetail(
    SkyMapViewModel vm,
    CatalogObject object,
  ) async {
    vm.selectObject(object);
    if (!mounted) return;
    await showSkyMapObjectDetailSheet(
      context: context,
      viewModel: vm,
      object: object,
    );
  }

  Future<void> _openConstellationObjects(
    SkyMapViewModel vm,
    SkyMapConstellationRender constellation,
  ) async {
    final selected = await showSkyMapConstellationObjectsSheet(
      context: context,
      viewModel: vm,
      constellationName: constellation.name,
    );
    if (!mounted || selected == null) return;
    await _openDetail(vm, selected);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SkyMapViewModel>();

    // 검색/필터는 성도 위(별도 행), 성도 캔버스는 그 아래 — 방위(N)가 가려지지 않음
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(vm),
            if (_showSearchResults) _buildSearchResults(vm),
            Expanded(
              child: ClipRect(
                child: _buildCanvas(vm),
              ),
            ),
            _buildBottomPanel(vm),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(SkyMapViewModel vm) {
    // 성도 배경·별자리와 겹쳐 보이지 않도록 완전 불투명 헤더
    return ColoredBox(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '천체 · 별 · 별자리 검색',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textPrimary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.textPrimary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            vm.clearSearch();
                            setState(() => _showSearchResults = false);
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setState(() => _showSearchResults = value.trim().isNotEmpty);
                },
                onSubmitted: (value) {
                  vm.setSearchQuery(value);
                  setState(() => _showSearchResults = false);
                  _searchFocus.unfocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () => showSkyMapFilterSheet(
                context: context,
                viewModel: vm,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.messier,
              ),
              icon: const Icon(Icons.filter_list),
              tooltip: '필터',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(SkyMapViewModel vm) {
    final results = vm.searchResults(_searchController.text);
    if (results.isEmpty) {
      return const ColoredBox(
        color: AppColors.surface,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '검색 결과 없음',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.surface,
      child: SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          itemCount: results.length,
          separatorBuilder: (context, index) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final hit = results[index];
            final color = switch (hit.kind) {
              SkyMapSearchKind.catalog =>
                hit.catalogObject?.catalog.accentColor ?? AppColors.messier,
              SkyMapSearchKind.star => AppColors.solar,
              SkyMapSearchKind.constellation => AppColors.messier,
            };
            return Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              child: ListTile(
              dense: true,
              leading: Text(
                hit.kindLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              title: Text(
                hit.title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                hit.subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
                onTap: () async {
                  _searchController.text = hit.title;
                  vm.clearSearch();
                  setState(() => _showSearchResults = false);
                  _searchFocus.unfocus();
                  if (hit.kind == SkyMapSearchKind.catalog &&
                      hit.catalogObject != null) {
                    await _openDetail(vm, hit.catalogObject!);
                  } else {
                    vm.focusOnSkyPosition(
                      raDeg: hit.raDeg,
                      decDeg: hit.decDeg,
                      preferredViewHeightDeg:
                          hit.kind == SkyMapSearchKind.constellation ? 50 : 35,
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCanvas(SkyMapViewModel vm) {
    if (vm.isLoading && !vm.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.errorMessage != null && !vm.hasLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '성도를 불러오지 못했습니다\n${vm.errorMessage}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: vm.load,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          vm.updateCanvasSize(size);
        });

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: Listener(
                // GestureDetector.onScale* 는 트랙패드 pan을 zoom으로 오인하므로 사용하지 않음.
                onPointerSignal: (event) {
                  if (event is! PointerScrollEvent) return;
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.windows &&
                      event.scrollDelta.dy != 0) {
                    // Windows wheel: 위=확대, 아래=축소. 이벤트 단위가
                    // 장치마다 달라 delta 크기를 완만한 배율로 정규화한다.
                    final rawAmount = event.scrollDelta.dy.abs() / 80;
                    final amount = rawAmount < 0.15
                        ? 0.15
                        : (rawAmount > 1.0 ? 1.0 : rawAmount);
                    final factor = 1 + amount * 0.25;
                    vm.setViewHeightDeg(
                      event.scrollDelta.dy < 0
                          ? vm.viewHeightDeg / factor
                          : vm.viewHeightDeg * factor,
                    );
                    return;
                  }
                  final delta = Offset(
                    -event.scrollDelta.dx,
                    -event.scrollDelta.dy,
                  );
                  if (delta.dx != 0 || delta.dy != 0) {
                    vm.panByPixels(delta);
                  }
                },
                onPointerPanZoomUpdate: (event) {
                  // 트랙패드 두 손가락 스크롤: pan만 (event.scale 무시)
                  if (event.panDelta.dx != 0 || event.panDelta.dy != 0) {
                    vm.panByPixels(event.panDelta);
                  }
                },
                onPointerDown: (event) => _onPointerDown(event, vm),
                onPointerMove: (event) => _onPointerMove(event, vm),
                onPointerUp: (event) => _onPointerUpOrCancel(event.pointer),
                onPointerCancel: (event) => _onPointerUpOrCancel(event.pointer),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) async {
                    // 천체 우선, 없으면 별자리 이름 라벨만 히트
                    final hit = vm.hitTest(details.localPosition);
                    if (hit?.source != null) {
                      await _openDetail(vm, hit!.source!);
                      return;
                    }
                    final constellation =
                        vm.hitTestConstellationLabel(details.localPosition);
                    if (constellation != null) {
                      await _openConstellationObjects(vm, constellation);
                    }
                  },
                  child: CustomPaint(
                    size: size,
                    isComplex: true,
                    willChange: true,
                    painter: SkyMapCompositePainter(
                      constellations: vm.visibleConstellations,
                      stars: vm.visibleStars,
                      objects: vm.visibleObjects,
                      selectedId: vm.selectedObject?.id,
                      fovCorners: vm.fovCorners,
                      showConstellations: vm.filters.showConstellations,
                      showStars: vm.filters.showBrightStars,
                      showLabels: vm.viewHeightDeg <= 90,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 12,
              top: 12,
              child: SkyMapSymbolLegend(),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                children: [
                  _zoomButton(
                    icon: Icons.add,
                    onPressed: () =>
                        vm.setViewHeightDeg(vm.viewHeightDeg / 1.25),
                  ),
                  const SizedBox(height: 8),
                  _zoomButton(
                    icon: Icons.remove,
                    onPressed: () =>
                        vm.setViewHeightDeg(vm.viewHeightDeg * 1.25),
                  ),
                  const SizedBox(height: 8),
                  _zoomButton(
                    icon: Icons.center_focus_strong,
                    onPressed: vm.resetView,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Text(
                  '${vm.visibleObjects.length} objects'
                  '${vm.filters.showBrightStars ? ' · ${vm.visibleStars.length} stars' : ''}'
                  ' · ${vm.viewHeightDeg.toStringAsFixed(0)}°',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _zoomButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: AppColors.textPrimary,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildBottomPanel(SkyMapViewModel vm) {
    final selected = vm.selectedObject;
    final fov = vm.fovPreview;
    final render = vm.selectedRenderObject;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      child: selected == null
          ? const Text(
              '천체를 선택하면 크기·위치·촬영 구도를 확인할 수 있습니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.displayName,
                            style: TextStyle(
                              color: selected.catalog.accentColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            selected.displayCommonName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openDetail(vm, selected),
                      child: const Text('상세'),
                    ),
                    IconButton(
                      onPressed: vm.clearSelection,
                      icon: const Icon(Icons.close),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
                Text(
                  'RA ${selected.ra}  ·  DEC ${selected.dec}'
                  '${render != null ? '  ·  ${render.sizeLabel}' : ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (vm.showFovOverlay && fov != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'FOV ${fov.equipmentName}  ${fov.fovLabel}',
                    style: const TextStyle(
                      color: AppColors.solar,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text(
                        '회전',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: fov.rotationDegrees.clamp(0, 180),
                          min: 0,
                          max: 180,
                          divisions: 4,
                          label: '${fov.rotationDegrees.round()}°',
                          activeColor: AppColors.solar,
                          onChanged: vm.setFovRotation,
                        ),
                      ),
                      Text(
                        '${fov.rotationDegrees.round()}°',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        tooltip: 'FOV 숨기기',
                        onPressed: vm.hideFovOverlay,
                        icon: const Icon(Icons.visibility_off_outlined),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
