import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../controller/horizon_measurement_controller.dart';
import '../models/horizon_measurement_result.dart';
import '../models/horizon_scan_sample.dart';
import '../services/device_orientation_service.dart';
import '../services/horizon_camera_service.dart';
import '../services/screen_awake_service.dart';

class HorizonScanScreen extends StatefulWidget {
  const HorizonScanScreen({
    super.key,
    required this.observationSiteId,
    required this.observationSiteName,
    this.latitude,
    this.longitude,
    this.controller,
    this.manageSystemOrientation = true,
    this.screenAwakeService = const MobileScreenAwakeService(),
  });

  final String observationSiteId;
  final String observationSiteName;
  final double? latitude;
  final double? longitude;
  final HorizonMeasurementController? controller;
  final bool manageSystemOrientation;
  final ScreenAwakeService screenAwakeService;

  @override
  State<HorizonScanScreen> createState() => _HorizonScanScreenState();
}

class _HorizonScanScreenState extends State<HorizonScanScreen>
    with WidgetsBindingObserver {
  late final HorizonMeasurementController _controller;
  late final bool _ownsController;
  bool _closing = false;
  bool _screenAwakeDesired = false;
  Future<void> _screenAwakeOperation = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        HorizonMeasurementController(
          observationSiteId: widget.observationSiteId,
          latitude: widget.latitude,
          longitude: widget.longitude,
          orientationService: context.read<DeviceOrientationService>(),
          cameraService: CameraPluginHorizonService(),
        );
    _controller.addListener(_onChanged);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed) {
      unawaited(_setScreenAwake(true));
    }
    if (widget.manageSystemOrientation) {
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_closing) unawaited(_setScreenAwake(true));
        unawaited(_controller.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_setScreenAwake(false));
        unawaited(_controller.pause());
      case AppLifecycleState.detached:
        unawaited(_setScreenAwake(false));
        unawaited(_controller.close());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    unawaited(_setScreenAwake(false));
    unawaited(_controller.close());
    if (_ownsController) _controller.dispose();
    if (widget.manageSystemOrientation) {
      unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      );
    }
    super.dispose();
  }

  Future<void> _cancelAndPop() async {
    if (_closing) return;
    _closing = true;
    await Future.wait([_controller.cancel(), _setScreenAwake(false)]);
    if (mounted) Navigator.of(context).pop<HorizonMeasurementResult>();
  }

  Future<void> _saveAndPop(HorizonMeasurementResult result) async {
    if (_closing) return;
    _closing = true;
    await Future.wait([_controller.close(), _setScreenAwake(false)]);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _setScreenAwake(bool enabled) {
    if (_screenAwakeDesired == enabled) return _screenAwakeOperation;
    _screenAwakeDesired = enabled;
    _screenAwakeOperation = _screenAwakeOperation.then((_) async {
      try {
        if (enabled) {
          await widget.screenAwakeService.enable();
        } else {
          await widget.screenAwakeService.disable();
        }
      } on Object catch (error) {
        debugPrint('화면 유지 상태 변경 실패: $error');
      }
    });
    return _screenAwakeOperation;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_cancelAndPop());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _cameraLayer(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent, Colors.black87],
                  stops: [0, 0.48, 1],
                ),
              ),
            ),
            SafeArea(
              child: _controller.status == HorizonMeasurementStatus.measuring
                  ? _measurementLayout()
                  : _nonMeasurementLayout(),
            ),
            if (_controller.status == HorizonMeasurementStatus.measuring)
              const _MeasurementCrosshair(),
          ],
        ),
      ),
    );
  }

  Widget _cameraLayer() {
    if (_controller.status != HorizonMeasurementStatus.measuring) {
      return const ColoredBox(color: Colors.black);
    }
    final camera = _controller.cameraController;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return Center(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: camera.value.previewSize!.height,
            height: camera.value.previewSize!.width,
            child: CameraPreview(camera),
          ),
        ),
      ),
    );
  }

  Widget _nonMeasurementLayout() {
    if (_controller.status == HorizonMeasurementStatus.summary) {
      return Column(
        children: [
          _topBar(),
          Expanded(child: SingleChildScrollView(child: _content())),
        ],
      );
    }
    return Column(children: [_topBar(), const Spacer(), _content()]);
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '시야 측정 도우미',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.observationSiteName.trim().isEmpty
                    ? '새 관측지'
                    : widget.observationSiteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('close-horizon-scan'),
          tooltip: '닫기',
          onPressed: _cancelAndPop,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _content() {
    return switch (_controller.status) {
      HorizonMeasurementStatus.introduction => _introduction(),
      HorizonMeasurementStatus.initializing => _messageCard(
        key: const Key('horizon-measurement-initializing'),
        icon: const CircularProgressIndicator(),
        title: '카메라와 방향 센서를 준비하고 있습니다.',
      ),
      HorizonMeasurementStatus.measuring => const SizedBox.shrink(),
      HorizonMeasurementStatus.summary => _summaryPanel(),
      HorizonMeasurementStatus.paused => _messageCard(
        key: const Key('horizon-measurement-paused'),
        icon: const Icon(Icons.pause_circle_outline, size: 38),
        title: '측정이 일시 중지되었습니다.',
        subtitle: '앱으로 돌아오면 자동으로 계속합니다.',
      ),
      HorizonMeasurementStatus.error => _errorPanel(),
      HorizonMeasurementStatus.cancelled => const SizedBox.shrink(),
    };
  }

  Widget _introduction() => Container(
    key: const Key('horizon-measurement-introduction'),
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.my_location, size: 42, color: AppColors.messier),
        const SizedBox(height: 12),
        const Text(
          '실제 망원경이 설치되는 위치에서 측정하세요.',
          key: Key('horizon-measurement-location-guide'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '휴대폰 카메라를 망원경의 렌즈 높이와 위치에 가깝게 놓으면 더 정확합니다. '
          '난간·창틀·천장처럼 가까운 장애물은 측정 위치에 따라 각도가 크게 달라질 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('start-horizon-measurement'),
          onPressed: () => unawaited(_controller.startMeasurement()),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('측정 시작'),
        ),
      ],
    ),
  );

  Widget _measurementLayout() => LayoutBuilder(
    key: const Key('horizon-measurement-ready'),
    builder: (context, constraints) {
      final panelHeight = (constraints.maxHeight * 0.35)
          .clamp(168.0, 280.0)
          .toDouble();
      return Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _topBar(),
                _measurementHud(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: panelHeight,
              child: _measurementControls(),
            ),
          ),
        ],
      );
    },
  );

  Widget _measurementHud() {
    final orientation = _controller.latestOrientation;
    final measurements = _controller.currentMeasurements;
    return Container(
      key: const Key('horizon-measurement-top-hud'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _liveOrientation(orientation),
          const SizedBox(height: 5),
          Text(
            '${_stepLabel(_controller.step)} · 측정 지점 ${measurements.length}개 · ${_controller.step.index + 1}/4',
            key: const Key('horizon-boundary-step'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            _stepInstruction(_controller.step),
            key: const Key('horizon-step-instruction'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (orientation?.accuracy == HorizonSensorAccuracy.low)
            const Text(
              '센서 정확도가 낮습니다. 휴대폰을 8자 모양으로 움직여 보정해 주세요.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.amber, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _measurementControls() {
    final measurements = _controller.currentMeasurements;
    return Container(
      key: const Key('horizon-measurement-bottom-panel'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('add-horizon-boundary-point'),
              onPressed: _controller.canAddPoint
                  ? _controller.addCurrentPoint
                  : null,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('지점 추가'),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Text(
                  '측정 지점 ${measurements.length}개',
                  key: const Key('horizon-boundary-point-count'),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('delete-last-horizon-boundary-point'),
                  onPressed: measurements.isEmpty
                      ? null
                      : _controller.deleteLastPoint,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('마지막 삭제'),
                ),
                TextButton(
                  key: const Key('reset-current-horizon-boundary'),
                  onPressed: measurements.isEmpty
                      ? null
                      : _controller.clearCurrentPoints,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('단계 초기화'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('horizon-boundary-points-scroll'),
              padding: EdgeInsets.zero,
              itemCount: measurements.length,
              itemBuilder: (context, index) {
                final point = measurements[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    '${_directionLabel(point.azimuth)} · ${point.azimuth.round()}° / ${point.altitude.round()}°',
                  ),
                  trailing: IconButton(
                    key: Key('delete-horizon-boundary-point-$index'),
                    tooltip: '지점 삭제',
                    onPressed: () => _controller.deletePoint(index),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                );
              },
            ),
          ),
          if (_controller.errorMessage != null) ...[
            Text(
              _controller.errorMessage!,
              key: const Key('horizon-measurement-validation-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amber),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (_controller.canGoBack) ...[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('previous-horizon-boundary-step'),
                    onPressed: _controller.previousStep,
                    child: const Text('이전'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  key: const Key('next-horizon-boundary-step'),
                  onPressed: () => unawaited(_controller.nextStep()),
                  child: Text(
                    _controller.step == HorizonBoundaryStep.lower
                        ? '결과 확인'
                        : '다음',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveOrientation(OrientationSample? orientation) => Container(
    key: const Key('horizon-live-orientation'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Text(
          orientation == null ? 'Az --°' : 'Az ${orientation.azimuth.round()}°',
          key: const Key('horizon-live-azimuth'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        Text(
          orientation == null ? '--' : _directionLabel(orientation.azimuth),
          key: const Key('horizon-live-direction'),
          style: const TextStyle(color: AppColors.messier),
        ),
        Text(
          orientation == null ? 'Alt --°' : 'Alt ${orientation.pitch.round()}°',
          key: const Key('horizon-live-altitude'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _summaryPanel() {
    final result = _controller.result!;
    final minimums = result.points.map((point) => point.minAltitude);
    final maximums = result.points.map((point) => point.maxAltitude ?? 90);
    final minLower = minimums.reduce((a, b) => a < b ? a : b);
    final maxLower = minimums.reduce((a, b) => a > b ? a : b);
    final minUpper = maximums.reduce((a, b) => a < b ? a : b);
    final maxUpper = maximums.reduce((a, b) => a > b ? a : b);
    return Container(
      key: const Key('horizon-measurement-summary'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.messier, size: 48),
          const SizedBox(height: 8),
          const Text(
            '시야 측정 결과',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            '촬영 가능 방향',
            result.mode == HorizonMeasurementMode.limited
                ? '${result.startAzimuth!.round()}° ~ ${result.endAzimuth!.round()}°'
                : '360° 전체',
          ),
          _summaryRow(
            '하단 경계',
            result.hasLowerBoundary
                ? '방향별 ${minLower.round()}° ~ ${maxLower.round()}°'
                : '제한 없음',
          ),
          _summaryRow(
            '상단 경계',
            result.hasUpperBoundary
                ? '방향별 ${minUpper.round()}° ~ ${maxUpper.round()}°'
                : '제한 없음',
          ),
          if (result.mode == HorizonMeasurementMode.limited)
            _summaryRow('차단 방향', '나머지 방위'),
          const Divider(height: 20),
          _summaryRow('왼쪽 측정 지점', '${result.leftMeasurements.length}개'),
          _summaryRow('오른쪽 측정 지점', '${result.rightMeasurements.length}개'),
          _summaryRow('상단 측정 지점', '${result.upperMeasurements.length}개'),
          _summaryRow('하단 측정 지점', '${result.lowerMeasurements.length}개'),
          _rawValues(result),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('restart-horizon-measurement'),
                  onPressed: () => unawaited(_controller.restart()),
                  child: const Text('다시 측정'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('save-horizon-measurement'),
                  onPressed: () => unawaited(_saveAndPop(result)),
                  child: const Text('저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorPanel() => _messageCard(
    key: const Key('horizon-measurement-error'),
    icon: const Icon(
      Icons.warning_amber_rounded,
      color: Colors.amber,
      size: 46,
    ),
    title: _controller.errorMessage ?? '시야 측정 도우미를 시작할 수 없습니다.',
    subtitle: '기존 수동 시야 설정은 계속 사용할 수 있습니다.',
    actions: [
      if (_controller.permissionPermanentlyDenied)
        OutlinedButton(
          key: const Key('open-camera-settings'),
          onPressed: openAppSettings,
          child: const Text('설정 열기'),
        ),
      FilledButton(
        key: const Key('close-horizon-measurement-error'),
        onPressed: _cancelAndPop,
        child: const Text('돌아가기'),
      ),
    ],
  );

  Widget _messageCard({
    required Key key,
    required Widget icon,
    required String title,
    String? subtitle,
    List<Widget> actions = const [],
  }) => Container(
    key: key,
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: actions),
        ],
      ],
    ),
  );

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _rawValues(HorizonMeasurementResult result) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: const Key('horizon-measurement-raw-values-toggle'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      shape: const RoundedRectangleBorder(),
      collapsedShape: const RoundedRectangleBorder(),
      title: const Text('측정값 보기'),
      children: [
        SizedBox(
          key: const Key('horizon-measurement-raw-values'),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rawSection(
                '왼쪽 경계',
                result.leftMeasurements,
                appliedAzimuth: result.startAzimuth,
              ),
              _rawSection(
                '오른쪽 경계',
                result.rightMeasurements,
                appliedAzimuth: result.endAzimuth,
              ),
              _rawSection('상단 경계', result.upperMeasurements),
              _rawSection('하단 경계', result.lowerMeasurements),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _rawSection(
    String label,
    List<HorizonBoundaryMeasurement> measurements, {
    double? appliedAzimuth,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (measurements.isEmpty)
          const Text(
            '측정하지 않음',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          for (final measurement in measurements)
            Text(
              '${_directionLabel(measurement.azimuth)} · Az ${_formatAngle(measurement.azimuth)} / Alt ${_formatAngle(measurement.altitude)}',
            ),
        if (appliedAzimuth != null)
          Text(
            '적용 방위 ${_formatAngle(appliedAzimuth)}',
            style: const TextStyle(color: AppColors.messier),
          ),
      ],
    ),
  );

  String _formatAngle(double value) => value == value.roundToDouble()
      ? '${value.round()}°'
      : '${value.toStringAsFixed(1)}°';

  String _stepLabel(HorizonBoundaryStep step) => switch (step) {
    HorizonBoundaryStep.left => '왼쪽 경계',
    HorizonBoundaryStep.right => '오른쪽 경계',
    HorizonBoundaryStep.upper => '상단 경계',
    HorizonBoundaryStep.lower => '하단 경계',
  };

  String _stepInstruction(HorizonBoundaryStep step) => switch (step) {
    HorizonBoundaryStep.left =>
      '왼쪽 경계가 있다면 지점을 추가하세요. 막혀 있지 않다면 바로 다음으로 넘어가세요.',
    HorizonBoundaryStep.right =>
      '오른쪽 경계가 있다면 지점을 추가하세요. 막혀 있지 않다면 바로 다음으로 넘어가세요.',
    HorizonBoundaryStep.upper =>
      '천장·처마·창틀 등 위쪽 경계를 따라 필요한 지점을 찍으세요. 완전히 열려 있다면 건너뛰세요.',
    HorizonBoundaryStep.lower =>
      '건물·산·나무·난간의 경계를 따라 높이가 크게 변하는 지점을 중심으로 찍으세요.',
  };

  String _directionLabel(double azimuth) {
    const labels = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
    final normalized = ((azimuth % 360) + 360) % 360;
    return labels[((normalized + 22.5) ~/ 45) % labels.length];
  }
}

class _MeasurementCrosshair extends StatelessWidget {
  const _MeasurementCrosshair();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Center(
      child: SizedBox.square(
        key: Key('horizon-measurement-crosshair'),
        dimension: 54,
        child: CustomPaint(painter: _CrosshairPainter()),
      ),
    ),
  );
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black87
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final foreground = Paint()
      ..color = AppColors.messier
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    for (final paint in [shadow, foreground]) {
      canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
      canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
      canvas.drawCircle(center, 8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
