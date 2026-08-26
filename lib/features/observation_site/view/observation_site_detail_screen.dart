import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/equipment.dart';
import '../../../data/models/horizon_point.dart';
import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../horizon_scan/view/horizon_scan_screen.dart';
import '../../settings/view/observation_site_edit_screen.dart';
import '../viewmodel/active_observation_site_view_model.dart';
import '../widgets/observation_site_horizon_summary.dart';

class ObservationSiteDetailScreen extends StatefulWidget {
  const ObservationSiteDetailScreen({
    super.key,
    required this.siteId,
    this.homeViewModel,
    this.activeViewModel,
    this.onOpenHorizonScan,
  });

  final String siteId;
  final HomeViewModel? homeViewModel;
  final ActiveObservationSiteViewModel? activeViewModel;
  final VoidCallback? onOpenHorizonScan;

  @override
  State<ObservationSiteDetailScreen> createState() =>
      _ObservationSiteDetailScreenState();
}

class _ObservationSiteDetailScreenState
    extends State<ObservationSiteDetailScreen> {
  ObservationSite? _site;
  List<Equipment> _equipment = const [];
  bool _loading = true;
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool activate = true}) async {
    final repository = context.read<ObservationSiteRepository>();
    final results = await Future.wait([
      repository.get(widget.siteId),
      context.read<EquipmentRepository>().getAll(activeOnly: true),
    ]);
    if (!mounted) return;
    final site = results[0] as ObservationSite?;
    setState(() {
      _site = site;
      _equipment = results[1] as List<Equipment>;
      _loading = false;
    });
    if (site != null && activate && !_activated) {
      _activated = true;
      await widget.activeViewModel?.selectSavedSite(site);
    }
  }

  Future<void> _updateSite(ObservationSite updated) async {
    await context.read<ObservationSiteRepository>().update(updated);
    if (!mounted) return;
    setState(() => _site = updated);
  }

  Future<void> _changeTracking(TrackingMode? mode) async {
    final site = _site;
    if (site == null || mode == null || mode == site.trackingMode) return;
    await _updateSite(
      site.copyWith(trackingMode: mode, updatedAt: DateTime.now()),
    );
  }

  Future<void> _changeEquipment(String? id) async {
    final site = _site;
    if (site == null || id == site.defaultEquipmentId) return;
    await _updateSite(
      site.copyWith(
        defaultEquipmentId: id,
        clearDefaultEquipment: id == null,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _openEditor() async {
    final site = _site;
    if (site == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ObservationSiteEditScreen(site: site)),
    );
    if (changed == true && mounted) {
      await _load(activate: false);
    }
  }

  Future<void> _openScan() async {
    if (widget.onOpenHorizonScan != null) {
      widget.onOpenHorizonScan!();
      return;
    }
    final site = _site;
    if (site == null) return;
    final points = await Navigator.of(context).push<List<HorizonPoint>>(
      MaterialPageRoute(
        builder: (_) => HorizonScanScreen(
          observationSiteId: site.id,
          observationSiteName: site.name,
          latitude: site.latitude,
          longitude: site.longitude,
        ),
      ),
    );
    if (!mounted || points == null) return;
    await _updateSite(
      site.copyWith(horizonPoints: points, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return Scaffold(
      appBar: AppBar(
        title: Text(site?.name ?? '관측지 상세'),
        actions: [
          if (site != null)
            IconButton(
              key: const Key('edit-observation-site-detail'),
              tooltip: '전체 정보 편집',
              onPressed: _openEditor,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : site == null
          ? const Center(child: Text('관측지를 찾을 수 없습니다.'))
          : AnimatedBuilder(
              animation: widget.homeViewModel ?? _NoopListenable.instance,
              builder: (context, _) => ListView(
                key: const Key('observation-site-detail'),
                padding: const EdgeInsets.all(16),
                children: [
                  _LocationHeader(site: site),
                  const Divider(height: 32),
                  _TodayConditions(
                    home: widget.homeViewModel,
                    bortle: site.bortle,
                  ),
                  const Divider(height: 32),
                  Text(
                    '오늘 사용할 설정',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TrackingMode>(
                    key: const Key('site-detail-tracking'),
                    initialValue: site.trackingMode,
                    decoration: const InputDecoration(labelText: '추적 방식'),
                    items: const [
                      DropdownMenuItem(
                        value: TrackingMode.altAz,
                        child: Text('Alt-Az'),
                      ),
                      DropdownMenuItem(
                        value: TrackingMode.eq,
                        child: Text('EQ'),
                      ),
                    ],
                    onChanged: _changeTracking,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: const Key('site-detail-equipment'),
                    initialValue: site.defaultEquipmentId,
                    decoration: const InputDecoration(labelText: '기본 장비'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('지정하지 않음'),
                      ),
                      ..._equipment.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: _changeEquipment,
                  ),
                  const Divider(height: 32),
                  ObservationSiteHorizonSummary(site: site),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('site-detail-horizon-scan'),
                    onPressed: _openScan,
                    icon: const Icon(Icons.panorama_horizontal_select_outlined),
                    label: const Text('시야 자동 측정 (Beta)'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '카메라로 주변 방향과 기울기를 확인합니다.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    key: const Key('site-detail-manual-horizon'),
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit_road_outlined),
                    label: const Text('막힌 방향·방향별 고도 직접 편집'),
                  ),
                  const Divider(height: 32),
                  _RecommendationSummary(home: widget.homeViewModel),
                  const Divider(height: 32),
                  _ScheduleSummary(home: widget.homeViewModel),
                ],
              ),
            ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({required this.site});
  final ObservationSite site;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(site.address?.trim().isNotEmpty == true ? site.address! : '주소 없음'),
      const SizedBox(height: 4),
      Text(
        '${site.latitude.toStringAsFixed(5)}, ${site.longitude.toStringAsFixed(5)}',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          Chip(label: Text('Bortle ${site.bortle?.toString() ?? '-'}')),
          Chip(
            label: Text(site.trackingMode == TrackingMode.eq ? 'EQ' : 'Alt-Az'),
          ),
          if (site.lastUsedAt != null) const Chip(label: Text('최근 사용')),
        ],
      ),
    ],
  );
}

class _RecommendationSummary extends StatelessWidget {
  const _RecommendationSummary({required this.home});
  final HomeViewModel? home;

  @override
  Widget build(BuildContext context) {
    final items = home?.recommendedObjects.take(4).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('이 관측지의 오늘 추천', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('표시할 추천 대상이 없습니다.')
        else
          ...items.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.object.displayName),
              subtitle: Text(
                [
                  if (item.observationWindow?.feasibleWindowSummary != null)
                    item.observationWindow!.feasibleWindowSummary!,
                  if (item.imagingAssessment != null)
                    item.imagingAssessment!.quality.label,
                ].join(' · '),
              ),
              trailing: Text('${item.score.round()}점'),
            ),
          ),
        TextButton(
          onPressed: home == null
              ? null
              : () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('전체 추천 보기'),
        ),
      ],
    );
  }
}

class _TodayConditions extends StatelessWidget {
  const _TodayConditions({required this.home, required this.bortle});

  final HomeViewModel? home;
  final int? bortle;

  @override
  Widget build(BuildContext context) {
    final condition = home?.observationCondition;
    final weather = condition?.weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘 조건', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (condition == null)
          const Text('오늘 조건을 불러오는 중입니다.')
        else ...[
          Text('관측 지수 ${condition.score}점 · ${condition.summaryText}'),
          if (weather != null)
            Text(
              '${weather.description} · ${weather.temperature.toStringAsFixed(1)}℃ · 구름 ${weather.cloudCoverage}%',
            ),
          Text('광해 Bortle ${bortle?.toString() ?? '-'}'),
          if (condition.recommendedWindow.isNotEmpty)
            Text('관측 가능 시간 ${condition.recommendedWindow}'),
        ],
      ],
    );
  }
}

class _ScheduleSummary extends StatelessWidget {
  const _ScheduleSummary({required this.home});
  final HomeViewModel? home;

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final items = home?.scheduleItems.take(3).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘 촬영 스케줄', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('생성된 스케줄이 없습니다.')
        else
          ...items.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.displayName),
              trailing: Text('${_time(item.startTime)}~${_time(item.endTime)}'),
            ),
          ),
        TextButton(
          onPressed: home == null
              ? null
              : () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('홈에서 스케줄 보기'),
        ),
      ],
    );
  }
}

class _NoopListenable extends ChangeNotifier {
  _NoopListenable._();
  static final instance = _NoopListenable._();
}
