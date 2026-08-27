import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/horizon_point.dart';
import '../controller/horizon_scan_controller.dart';
import '../models/horizon_scan_sample.dart';
import '../models/horizon_scan_session.dart';
import '../services/device_orientation_service.dart';
import '../services/horizon_camera_service.dart';
import '../services/horizon_scan_sampler.dart';
import '../../observation_site/widgets/horizon_visibility_overview.dart';

class HorizonScanScreen extends StatefulWidget {
  const HorizonScanScreen({
    super.key,
    required this.observationSiteId,
    required this.observationSiteName,
    this.latitude,
    this.longitude,
    this.controller,
    this.manageSystemOrientation = true,
  });

  final String observationSiteId;
  final String observationSiteName;
  final double? latitude;
  final double? longitude;
  final HorizonScanController? controller;
  final bool manageSystemOrientation;

  @override
  State<HorizonScanScreen> createState() => _HorizonScanScreenState();
}

class _HorizonScanScreenState extends State<HorizonScanScreen>
    with WidgetsBindingObserver {
  late final HorizonScanController _controller;
  late final bool _ownsController;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        HorizonScanController(
          observationSiteId: widget.observationSiteId,
          observationSiteName: widget.observationSiteName,
          latitude: widget.latitude,
          longitude: widget.longitude,
          orientationService: context.read<DeviceOrientationService>(),
          cameraService: CameraPluginHorizonService(),
        );
    _controller.addListener(_onChanged);
    if (widget.manageSystemOrientation) {
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
    unawaited(_controller.initialize());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.resume());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_controller.pause());
      case AppLifecycleState.detached:
        unawaited(_controller.close());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
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
    await _controller.cancel();
    if (mounted) Navigator.of(context).pop<List<HorizonPoint>>();
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
            if (_controller.session.status == HorizonScanStatus.scanning)
              _levelGuide(),
            SafeArea(
              child: Column(children: [_topBar(), const Spacer(), _content()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraLayer() {
    if (_controller.session.status != HorizonScanStatus.scanning) {
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

  Widget _topBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '시야 자동 측정',
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

  Widget _levelGuide() => Center(
    child: Row(
      children: [
        const Expanded(child: Divider(color: Colors.white70, thickness: 1)),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: AppColors.messier, width: 2),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white70, thickness: 1)),
      ],
    ),
  );

  Widget _content() {
    return switch (_controller.session.status) {
      HorizonScanStatus.initializing || HorizonScanStatus.idle => _messageCard(
        key: const Key('horizon-scan-initializing'),
        icon: const CircularProgressIndicator(),
        title: '카메라와 방향 센서를 준비하고 있습니다.',
      ),
      HorizonScanStatus.scanning => _scanPanel(),
      HorizonScanStatus.paused => _messageCard(
        key: const Key('horizon-scan-paused'),
        icon: const Icon(Icons.pause_circle_outline, size: 38),
        title: '측정이 일시 중지되었습니다.',
        subtitle: '앱으로 돌아오면 자동으로 계속합니다.',
      ),
      HorizonScanStatus.processing => _messageCard(
        key: const Key('horizon-scan-processing'),
        icon: const CircularProgressIndicator(),
        title: '카메라와 센서를 정리하고 측정 결과를 만들고 있습니다.',
      ),
      HorizonScanStatus.completed => _summaryPanel(),
      HorizonScanStatus.error => _errorPanel(),
      HorizonScanStatus.cancelled => const SizedBox.shrink(),
    };
  }

  Widget _scanPanel() {
    final orientation = _controller.latestOrientation;
    final session = _controller.session;
    return Container(
      key: const Key('horizon-scan-ready'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '휴대폰을 세운 상태로 천천히 한 바퀴 돌아주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _value('방위각', '${orientation?.azimuth.round() ?? '-'}°'),
              _value(
                'Pitch',
                orientation == null
                    ? '-'
                    : '${orientation.pitch >= 0 ? '+' : ''}${orientation.pitch.toStringAsFixed(1)}°',
              ),
              _value('샘플', '${session.sampleCount}/72'),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            key: const Key('horizon-scan-progress'),
            value: _controller.coverage,
            minHeight: 9,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          Text('방향 커버리지 ${(_controller.coverage * 100).round()}%'),
          const SizedBox(height: 8),
          Text(
            _guideText(session, orientation),
            key: const Key('horizon-scan-guide'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: session.speedGuide == HorizonSpeedGuide.tooFast
                  ? Colors.amber
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (orientation?.accuracy == HorizonSensorAccuracy.low) ...[
            const SizedBox(height: 8),
            const Text(
              '방향 센서 정확도가 낮습니다. 휴대폰을 8자 모양으로 움직여 보정해 주세요.',
              key: Key('horizon-scan-low-accuracy'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amber),
            ),
          ],
        ],
      ),
    );
  }

  String _guideText(
    HorizonScanSession session,
    OrientationSample? orientation,
  ) {
    if (orientation == null) return '방향 센서를 확인하고 있습니다.';
    if (session.speedGuide == HorizonSpeedGuide.tooFast) {
      return '조금 천천히 움직여 주세요.';
    }
    return switch (session.pitchGuide) {
      HorizonPitchGuide.tiltUp => '카메라를 조금 위로 올려 주세요.',
      HorizonPitchGuide.tiltDown => '카메라를 조금 아래로 내려 주세요.',
      HorizonPitchGuide.level =>
        session.direction == null
            ? '천천히 한 방향으로 돌아 주세요.'
            : '천천히 같은 방향으로 돌아 주세요.',
    };
  }

  Widget _summaryPanel() {
    final session = _controller.session;
    final accuracy = session.samples.isEmpty
        ? HorizonSensorAccuracy.unknown
        : session.samples.last.sensorAccuracy;
    return Container(
      key: const Key('horizon-scan-summary'),
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
            '시야 스캔 완료',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            '측정 범위',
            '${session.coveredBins.length * HorizonScanSampler.binSizeDegrees ~/ 1}° / 360°',
          ),
          _summaryRow('샘플', '${session.sampleCount} / 72'),
          _summaryRow('방향 센서', _accuracyLabel(accuracy)),
          _summaryRow('생성된 시야 지점', '${_controller.horizonPoints.length}개'),
          _summaryRow(
            '평균 회전 속도',
            '${session.averageSpeed.toStringAsFixed(1)}°/초',
          ),
          if (_controller.missingBins.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '일부 방향의 측정값이 부족합니다. 그래도 계속할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.amber),
            ),
          ],
          const SizedBox(height: 10),
          HorizonVisibilityOverview(
            points: _controller.horizonPoints,
            blockedRanges: const [],
            showUnmeasured: _controller.missingBins.isNotEmpty,
          ),
          if (_controller.horizonPoints.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              key: const Key('horizon-scan-preview'),
              spacing: 6,
              runSpacing: 6,
              children: _previewPoints(_controller.horizonPoints)
                  .map(
                    (point) => Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${_directionLabel(point.azimuth)} ${point.minAltitude.round()}°',
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('restart-horizon-scan'),
                  onPressed: _controller.restart,
                  child: const Text('다시 측정'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('finish-horizon-scan'),
                  onPressed: _controller.horizonPoints.isEmpty
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(_controller.horizonPoints),
                  child: const Text('적용'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '완료하면 측정값이 관측지의 실제 시야 미리보기에 반영됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _errorPanel() => _messageCard(
    key: const Key('horizon-scan-error'),
    icon: const Icon(
      Icons.warning_amber_rounded,
      color: Colors.amber,
      size: 46,
    ),
    title: _controller.errorMessage ?? '자동 시야 측정을 시작할 수 없습니다.',
    subtitle: '기존 수동 Horizon 설정은 계속 사용할 수 있습니다.',
    actions: [
      if (_controller.permissionPermanentlyDenied)
        OutlinedButton(
          key: const Key('open-camera-settings'),
          onPressed: openAppSettings,
          child: const Text('설정 열기'),
        ),
      FilledButton(
        key: const Key('close-horizon-scan-error'),
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

  Widget _value(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(value),
      ],
    ),
  );

  String _accuracyLabel(HorizonSensorAccuracy accuracy) => switch (accuracy) {
    HorizonSensorAccuracy.good => '양호',
    HorizonSensorAccuracy.medium => '보통',
    HorizonSensorAccuracy.low => '낮음',
    HorizonSensorAccuracy.unknown => '알 수 없음',
  };

  List<HorizonPoint> _previewPoints(List<HorizonPoint> points) => [
    for (var azimuth = 0; azimuth < 360; azimuth += 45)
      points.reduce(
        (a, b) =>
            (a.azimuth - azimuth).abs() <= (b.azimuth - azimuth).abs() ? a : b,
      ),
  ];

  String _directionLabel(double azimuth) {
    const labels = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
    return labels[((azimuth + 22.5) ~/ 45) % labels.length];
  }
}
