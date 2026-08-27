import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/horizon_point.dart';
import '../../../data/models/imaging_suitability_assessment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/site_horizon_profile.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/horizon_visibility_service.dart';
import '../../../services/location_service.dart';
import '../../../services/observation_condition_service.dart';
import '../../../services/observation_site_validator.dart';
import '../../horizon_scan/view/horizon_scan_screen.dart';
import '../../observation_site/widgets/horizon_visibility_overview.dart';
import '../widgets/observation_location_search_sheet.dart';

class ObservationSiteEditScreen extends StatefulWidget {
  const ObservationSiteEditScreen({
    super.key,
    this.site,
    this.initialLatitude,
    this.initialLongitude,
  });

  final ObservationSite? site;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<ObservationSiteEditScreen> createState() =>
      _ObservationSiteEditScreenState();
}

class _ObservationSiteEditScreenState extends State<ObservationSiteEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  late final String _siteId;
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _bortle;
  late final TextEditingController _sqm;
  late final TextEditingController _memo;
  late TrackingMode _trackingMode;
  String? _defaultEquipmentId;
  late bool _favorite;
  late List<HorizonPoint> _points;
  late List<BlockedAzimuthRange> _blockedRanges;
  List<Equipment> _equipment = const [];
  bool _saving = false;
  bool _derivingSkyQuality = false;
  double? _lastDerivedLatitude;
  double? _lastDerivedLongitude;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _siteId = site?.id ?? _uuid.v4();
    _name = TextEditingController(text: site?.name);
    _address = TextEditingController(text: site?.address);
    _latitude = TextEditingController(
      text: (site?.latitude ?? widget.initialLatitude)?.toString(),
    );
    _longitude = TextEditingController(
      text: (site?.longitude ?? widget.initialLongitude)?.toString(),
    );
    _bortle = TextEditingController(text: site?.bortle?.toString());
    _sqm = TextEditingController(text: site?.sqm?.toString());
    if (site?.bortle != null && site?.sqm != null) {
      _lastDerivedLatitude = site?.latitude;
      _lastDerivedLongitude = site?.longitude;
    }
    _memo = TextEditingController(text: site?.memo);
    _trackingMode = site?.trackingMode ?? TrackingMode.altAz;
    _defaultEquipmentId = site?.defaultEquipmentId;
    _favorite = site?.isFavorite ?? true;
    _points = List.of(site?.horizonPoints ?? const []);
    _blockedRanges = List.of(site?.blockedAzimuthRanges ?? const []);
    unawaited(_loadEquipment());
    final initialLatitude = _double(_latitude);
    final initialLongitude = _double(_longitude);
    if (site == null && initialLatitude != null && initialLongitude != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_deriveSkyQuality(initialLatitude, initialLongitude));
      });
    }
  }

  Future<void> _loadEquipment() async {
    final equipment = await context.read<EquipmentRepository>().getAll();
    if (!mounted) return;
    setState(() {
      _equipment = equipment;
      if (_defaultEquipmentId != null &&
          !equipment.any((item) => item.id == _defaultEquipmentId)) {
        _defaultEquipmentId = null;
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _latitude,
      _longitude,
      _bortle,
      _sqm,
      _memo,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _double(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  int? _int(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _useCurrentLocation() async {
    try {
      final locationService = context.read<LocationService>();
      final geocodingService = context.read<GeocodingService>();
      final conditionService = context.read<ObservationConditionService>();
      setState(() => _derivingSkyQuality = true);
      final location = await locationService.getCurrentLocation();
      final info = await geocodingService.getLocationInfo(
        location.latitude,
        location.longitude,
      );
      final condition = await conditionService.getConditionAt(
        location.latitude,
        location.longitude,
      );
      if (condition.bortle == null || condition.sqm == null) {
        throw StateError('현재 위치의 Bortle/SQM을 계산할 수 없습니다.');
      }
      if (!mounted) return;
      setState(() {
        _address.text = info == null
            ? '현재 위치'
            : (info.address.isNotEmpty ? info.address : info.locationName);
        _latitude.text = location.latitude.toStringAsFixed(6);
        _longitude.text = location.longitude.toStringAsFixed(6);
        _bortle.text = condition.bortle.toString();
        _sqm.text = condition.sqm!.toStringAsFixed(2);
        _lastDerivedLatitude = location.latitude;
        _lastDerivedLongitude = location.longitude;
      });
    } catch (error) {
      if (mounted) _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _derivingSkyQuality = false);
    }
  }

  Future<void> _openHorizonScan() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final points = await Navigator.of(context).push<List<HorizonPoint>>(
      MaterialPageRoute(
        builder: (_) => HorizonScanScreen(
          observationSiteId: _siteId,
          observationSiteName: _name.text.trim(),
          latitude: _double(_latitude),
          longitude: _double(_longitude),
        ),
      ),
    );
    if (!mounted || points == null) return;
    setState(() {
      _points = points;
    });
  }

  Future<void> _searchAddress() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final geocoding = context.read<GeocodingService>();
    final selected = await ObservationLocationSearchSheet.show(
      context,
      geocodingService: geocoding,
    );
    if (!mounted || selected == null) return;
    await _applyLocationSelection(geocoding, selected);
  }

  Future<void> _applyLocationSelection(
    GeocodingService geocoding,
    LocationSearchSuggestion selected,
  ) async {
    final conditionService = context.read<ObservationConditionService>();
    setState(() => _derivingSkyQuality = true);
    try {
      GeocodeForwardResult? result;
      if (selected.hasCoordinates) {
        result = GeocodeForwardResult(
          latitude: selected.latitude!,
          longitude: selected.longitude!,
          formattedAddress: selected.secondaryText ?? selected.mainText,
          placeName: selected.mainText,
        );
      } else if (selected.hasPlaceId) {
        result = await geocoding.getPlaceDetails(selected.placeId!);
      }
      if (result == null) throw StateError('선택한 장소의 좌표를 찾을 수 없습니다.');
      final condition = await conditionService.getConditionAt(
        result.latitude,
        result.longitude,
      );
      if (condition.bortle == null || condition.sqm == null) {
        throw StateError('선택한 위치의 Bortle/SQM을 계산할 수 없습니다.');
      }
      if (!mounted) return;
      setState(() {
        _address.text = result!.displayLabel;
        _latitude.text = result.latitude.toStringAsFixed(6);
        _longitude.text = result.longitude.toStringAsFixed(6);
        _bortle.text = condition.bortle?.toString() ?? '';
        _sqm.text = condition.sqm?.toStringAsFixed(2) ?? '';
        _lastDerivedLatitude = result.latitude;
        _lastDerivedLongitude = result.longitude;
      });
    } catch (_) {
      if (mounted) _showError('위치 정보를 적용하지 못했습니다. 기존 위치는 유지됩니다.');
    } finally {
      if (mounted) setState(() => _derivingSkyQuality = false);
    }
  }

  Future<void> _deriveSkyQuality(double latitude, double longitude) async {
    if (!mounted) return;
    ObservationConditionService service;
    try {
      service = context.read<ObservationConditionService>();
    } on ProviderNotFoundException {
      return;
    }
    setState(() => _derivingSkyQuality = true);
    try {
      final condition = await service.getConditionAt(latitude, longitude);
      if (!mounted) return;
      _bortle.text = condition.bortle?.toString() ?? '';
      _sqm.text = condition.sqm?.toStringAsFixed(2) ?? '';
      _lastDerivedLatitude = latitude;
      _lastDerivedLongitude = longitude;
    } finally {
      if (mounted) setState(() => _derivingSkyQuality = false);
    }
  }

  Future<void> _resolveLocationContextBeforeSave() async {
    var latitude = _double(_latitude);
    var longitude = _double(_longitude);
    if (latitude == null || longitude == null) return;
    final needsDerivation =
        _lastDerivedLatitude != latitude || _lastDerivedLongitude != longitude;
    if (needsDerivation) await _deriveSkyQuality(latitude, longitude);
  }

  Future<void> _editHorizonPoint([HorizonPoint? existing]) async {
    var azimuth = existing?.azimuth.toString() ?? '';
    var min = existing?.minAltitude.toString() ?? '';
    var max = existing?.maxAltitude?.toString() ?? '';
    final result = await showDialog<HorizonPoint>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '방향별 고도 추가' : '방향별 고도 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogNumberField(
                key: const Key('horizon-azimuth'),
                initialValue: azimuth,
                label: '방위각 (°)',
                onChanged: (value) => azimuth = value,
              ),
              _dialogNumberField(
                key: const Key('horizon-min-altitude'),
                initialValue: min,
                label: '최소 고도 (°)',
                onChanged: (value) => min = value,
              ),
              _dialogNumberField(
                key: const Key('horizon-max-altitude'),
                initialValue: max,
                label: '최대 고도 (°, 선택)',
                onChanged: (value) => max = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final point = HorizonPoint(
                id: existing?.id ?? _uuid.v4(),
                observationSiteId: _siteId,
                azimuth: double.tryParse(azimuth) ?? double.nan,
                minAltitude: double.tryParse(min) ?? double.nan,
                maxAltitude: max.trim().isEmpty ? null : double.tryParse(max),
                sortOrder: existing?.sortOrder ?? _points.length,
                source: existing?.source ?? HorizonDataSource.manual,
              );
              try {
                ObservationSiteValidator.validateHorizonPoint(point);
                final duplicate = _points.any(
                  (item) =>
                      item.id != point.id && item.azimuth == point.azimuth,
                );
                if (duplicate) throw ArgumentError('같은 방위각이 이미 있습니다.');
                Navigator.pop(context, point);
              } catch (error) {
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(SnackBar(content: Text(_message(error))));
              }
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _points.indexWhere((point) => point.id == result.id);
      if (index < 0) {
        _points.add(result);
      } else {
        _points[index] = result;
      }
      _points.sort((a, b) => a.azimuth.compareTo(b.azimuth));
    });
  }

  SiteHorizonProfile get _horizonProfile =>
      SiteHorizonProfile(points: _points, blockedRanges: _blockedRanges);

  double _directionAltitude(double azimuth) {
    return const HorizonVisibilityService().minimumVisibleAltitude(
      _horizonProfile,
      azimuth,
    );
  }

  void _setDirectionAltitude(double azimuth, double altitude) {
    setState(() {
      if (_points.isEmpty) {
        for (final direction in _horizonDirections) {
          _points.add(
            HorizonPoint(
              id: _uuid.v4(),
              observationSiteId: _siteId,
              azimuth: direction.$1,
              minAltitude: 0,
              sortOrder: _points.length,
            ),
          );
        }
      }

      final index = _points.indexWhere(
        (point) => (point.azimuth - azimuth).abs() < 1e-9,
      );
      if (index == -1) {
        _points.add(
          HorizonPoint(
            id: _uuid.v4(),
            observationSiteId: _siteId,
            azimuth: azimuth,
            minAltitude: altitude,
            sortOrder: _points.length,
          ),
        );
      } else {
        _points[index] = _points[index].copyWith(minAltitude: altitude);
      }
      _points.sort((a, b) => a.azimuth.compareTo(b.azimuth));
    });
  }

  void _clearHorizon() {
    setState(() {
      _points.clear();
      _blockedRanges.clear();
    });
  }

  Future<void> _editBlockedRange([BlockedAzimuthRange? existing]) async {
    var start = existing?.startAzimuth.toString() ?? '';
    var end = existing?.endAzimuth.toString() ?? '';
    var reason = existing?.reason ?? '';
    final result = await showDialog<BlockedAzimuthRange>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '막힌 방향 추가' : '막힌 방향 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogNumberField(
                key: const Key('blocked-range-start'),
                initialValue: start,
                label: '시작 방위각 (°)',
                onChanged: (value) => start = value,
              ),
              _dialogNumberField(
                key: const Key('blocked-range-end'),
                initialValue: end,
                label: '종료 방위각 (°)',
                onChanged: (value) => end = value,
              ),
              TextFormField(
                initialValue: reason,
                onChanged: (value) => reason = value,
                decoration: const InputDecoration(labelText: '사유 (선택)'),
              ),
              const SizedBox(height: 8),
              const Text(
                '350° → 20°처럼 북쪽(0°)을 지나는 구간도 허용됩니다.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final range = BlockedAzimuthRange(
                id: existing?.id ?? _uuid.v4(),
                observationSiteId: _siteId,
                startAzimuth: double.tryParse(start) ?? double.nan,
                endAzimuth: double.tryParse(end) ?? double.nan,
                reason: reason.trim().isEmpty ? null : reason.trim(),
                source: existing?.source ?? HorizonDataSource.manual,
              );
              try {
                ObservationSiteValidator.validateBlockedRange(range);
                Navigator.pop(context, range);
              } catch (error) {
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(SnackBar(content: Text(_message(error))));
              }
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = _blockedRanges.indexWhere((range) => range.id == result.id);
      if (index < 0) {
        _blockedRanges.add(result);
      } else {
        _blockedRanges[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _resolveLocationContextBeforeSave();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('위치 기반 하늘 품질을 계산하지 못했습니다: ${_message(error)}');
      }
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final site = ObservationSite(
      id: _siteId,
      name: _name.text.trim(),
      address: _optional(_address),
      latitude: _double(_latitude) ?? double.nan,
      longitude: _double(_longitude) ?? double.nan,
      bortle: _int(_bortle),
      sqm: _double(_sqm),
      brightnessGrade: widget.site?.brightnessGrade,
      isFavorite: _favorite,
      trackingMode: _trackingMode,
      defaultEquipmentId: _defaultEquipmentId,
      // v32 legacy columns are preserved for existing installations. Actual
      // visibility is now owned by the direction-based Horizon profile.
      defaultMinAltitude: widget.site?.defaultMinAltitude ?? 20,
      defaultMaxAltitude: widget.site?.defaultMaxAltitude,
      // Legacy storage columns are retained, but no longer affect runtime.
      preferredStart: widget.site?.preferredStart,
      preferredEnd: widget.site?.preferredEnd,
      memo: _memo.text.trim(),
      createdAt: widget.site?.createdAt ?? now,
      updatedAt: now,
      lastUsedAt: widget.site?.lastUsedAt,
      horizonPoints: _points,
      blockedAzimuthRanges: _blockedRanges,
    );
    try {
      ObservationSiteValidator.validate(site);
      final repository = context.read<ObservationSiteRepository>();
      if (widget.site == null) {
        await repository.create(site);
      } else {
        await repository.update(site);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(_message(error));
      }
    }
  }

  Future<void> _delete() async {
    if (widget.site == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('관측지 삭제'),
            content: const Text('관측지를 삭제할까요? 기존 사진 기록의 위치는 유지됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await context.read<ObservationSiteRepository>().delete(_siteId);
    if (mounted) Navigator.pop(context, true);
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Invalid argument(s): ', '')
      .replaceFirst('Invalid argument ', '')
      .replaceFirst('ArgumentError: ', '');

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.site == null ? '관측지 추가' : '관측지 수정'),
        actions: [
          if (widget.site != null)
            IconButton(
              key: const Key('delete-observation-site'),
              tooltip: '삭제',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('기본 정보'),
            _textField(
              _name,
              '관측지 이름',
              required: true,
              key: const Key('site-name'),
            ),
            TextFormField(
              key: const Key('site-location-selection'),
              controller: _address,
              readOnly: true,
              onTap: _saving ? null : _searchAddress,
              decoration: const InputDecoration(
                labelText: '관측 위치',
                hintText: '주소 또는 장소 검색',
                prefixIcon: Icon(Icons.place_outlined),
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _searchAddress,
                    icon: const Icon(Icons.search),
                    label: const Text('위치 검색'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _useCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('현재 위치'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    _latitude,
                    '위도 (-90~90)',
                    key: const Key('site-latitude'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    _longitude,
                    '경도 (-180~180)',
                    key: const Key('site-longitude'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    _bortle,
                    'Bortle (자동)',
                    key: const Key('site-bortle'),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    _sqm,
                    'SQM (자동)',
                    key: const Key('site-sqm'),
                    readOnly: true,
                  ),
                ),
              ],
            ),
            if (_derivingSkyQuality)
              const LinearProgressIndicator(key: Key('sky-quality-progress')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('즐겨찾기'),
              value: _favorite,
              onChanged: (value) => setState(() => _favorite = value),
            ),
            _sectionTitle('촬영 설정'),
            DropdownButtonFormField<TrackingMode>(
              initialValue: _trackingMode,
              decoration: const InputDecoration(labelText: '추적 방식'),
              items: const [
                DropdownMenuItem(
                  value: TrackingMode.altAz,
                  child: Text('Alt-Az'),
                ),
                DropdownMenuItem(value: TrackingMode.eq, child: Text('EQ')),
              ],
              onChanged: (value) =>
                  setState(() => _trackingMode = value ?? TrackingMode.altAz),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _defaultEquipmentId,
              decoration: const InputDecoration(labelText: '기본 장비'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('지정 안 함'),
                ),
                if (_defaultEquipmentId != null &&
                    !_equipment.any(
                      (equipment) => equipment.id == _defaultEquipmentId,
                    ))
                  DropdownMenuItem<String?>(
                    value: _defaultEquipmentId,
                    child: const Text('저장된 장비'),
                  ),
                ..._equipment.map(
                  (equipment) => DropdownMenuItem<String?>(
                    value: equipment.id,
                    child: Text(equipment.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _defaultEquipmentId = value),
            ),
            _textField(_memo, '메모', maxLines: 3),
            _sectionTitle('촬영 가능 시야'),
            Text(
              _horizonProfile.hasRestrictions ? '실제 시야: 등록됨' : '실제 시야: 제한 없음',
              key: const Key('horizon-registration-status'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              '건물·산·나무 때문에 가려지는 높이를 대표 방향별로 대략 설정합니다. '
              '방향 사이는 자동으로 이어집니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            HorizonVisibilityOverview(
              points: _points,
              blockedRanges: _blockedRanges,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('start-horizon-scan'),
              onPressed: _openHorizonScan,
              icon: const Icon(Icons.panorama_horizontal_select_outlined),
              label: const Text('카메라로 시야 자동 스캔'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 12),
              child: Text(
                '한 바퀴 천천히 돌면 자동 측정값을 먼저 만들고 아래에서 미리보기를 확인합니다.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            Text('필요 시 수동 보정', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            ..._horizonDirections.map(
              (direction) => _HorizonDirectionSlider(
                key: Key('horizon-direction-${direction.$1.toInt()}'),
                azimuth: direction.$1,
                direction: direction.$2,
                altitude: _directionAltitude(direction.$1),
                onChanged: (value) =>
                    _setDirectionAltitude(direction.$1, value),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('clear-horizon'),
                onPressed: _horizonProfile.hasRestrictions
                    ? _clearHorizon
                    : null,
                icon: const Icon(Icons.clear_all),
                label: const Text('시야 제한 없음'),
              ),
            ),
            Text('막힌 방향', style: Theme.of(context).textTheme.titleSmall),
            ..._blockedRanges.map(
              (range) => ListTile(
                key: Key('blocked-range-${range.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('${range.startAzimuth}° → ${range.endAzimuth}°'),
                subtitle: range.reason == null ? null : Text(range.reason!),
                onTap: () => _editBlockedRange(range),
                trailing: IconButton(
                  onPressed: () => setState(() => _blockedRanges.remove(range)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('add-blocked-range'),
              onPressed: _editBlockedRange,
              icon: const Icon(Icons.add),
              label: const Text('막힌 방향 추가'),
            ),
            const SizedBox(height: 16),
            Text('세부 방향 지점', style: Theme.of(context).textTheme.titleSmall),
            ..._points.map(
              (point) => ListTile(
                key: Key('horizon-point-${point.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('방향 ${point.azimuth}°'),
                subtitle: Text(
                  '최소 가시 고도 ${point.minAltitude.toStringAsFixed(0)}°',
                ),
                onTap: () => _editHorizonPoint(point),
                trailing: IconButton(
                  onPressed: () => setState(() => _points.remove(point)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('add-horizon-point'),
              onPressed: _editHorizonPoint,
              icon: const Icon(Icons.add),
              label: const Text('방향별 고도 추가'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('save-observation-site'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.messier,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: key,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value?.trim().isEmpty == true ? '$label은 필수입니다.' : null
            : null,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    Key? key,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: key,
        controller: controller,
        readOnly: readOnly,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _dialogNumberField({
    Key? key,
    required String initialValue,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: key,
        initialValue: initialValue,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

const _horizonDirections = <(double, String)>[
  (0, '북'),
  (45, '북동'),
  (90, '동'),
  (135, '남동'),
  (180, '남'),
  (225, '남서'),
  (270, '서'),
  (315, '북서'),
];

class _HorizonDirectionSlider extends StatelessWidget {
  const _HorizonDirectionSlider({
    super.key,
    required this.azimuth,
    required this.direction,
    required this.altitude,
    required this.onChanged,
  });

  final double azimuth;
  final String direction;
  final double altitude;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 70,
        child: Text('$direction ${azimuth.toStringAsFixed(0)}°'),
      ),
      Expanded(
        child: Slider(
          value: altitude.clamp(0, 90),
          min: 0,
          max: 90,
          divisions: 18,
          label: '${altitude.round()}°',
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 36,
        child: Text('${altitude.round()}°', textAlign: TextAlign.end),
      ),
    ],
  );
}
