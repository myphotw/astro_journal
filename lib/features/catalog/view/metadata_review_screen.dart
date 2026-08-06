import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/exif_info.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/api_key_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/metadata_field_trace.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_registration_service.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../../shared/widgets/integration_minutes_field.dart';
import '../../../shared/widgets/material_date_time_picker_field.dart';

/// 메타데이터 자동 입력 결과를 사용자에게 보여주고 수정할 수 있는 화면.
class MetadataReviewScreen extends StatefulWidget {
  const MetadataReviewScreen({
    super.key,
    required this.photoPath,
    required this.exifInfo,
    required this.objectDisplayId,
    required this.objectName,
  });

  final String photoPath;
  final ExifInfo exifInfo;
  final String objectDisplayId;
  final String objectName;

  @override
  State<MetadataReviewScreen> createState() => _MetadataReviewScreenState();
}

class _MetadataReviewScreenState extends State<MetadataReviewScreen> {
  late final TextEditingController _targetNameCtrl;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _locationNameCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _stackNumCtrl;
  late final TextEditingController _singleExpSecCtrl;
  late final TextEditingController _totalExpSecCtrl;
  late final TextEditingController _filterCtrl;
  late final TextEditingController _isoCtrl;
  late final TextEditingController _fstopCtrl;
  late final TextEditingController _focalCtrl;

  DateTime? _capturedAt;
  List<Equipment> _equipmentList = const [];
  String? _selectedEquipmentName;

  final ValueNotifier<String?> _geocodedLocation = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _isGeocoding = ValueNotifier<bool>(false);
  /// 첫 프레임 이후 지도를 붙여 PlatformView 전환 버벅임을 줄인다.
  final ValueNotifier<bool> _showMap = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      MetadataFieldTrace.logExifInfo('ReviewScreen.Input', widget.exifInfo);
      MetadataFieldTrace.logUiValues('MetadataReview', widget.exifInfo);
    }
    _initControllers();
    _loadEquipment();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchLocationName();
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _showMap.value = true;
      });
    });
  }

  void _initControllers() {
    final exif = widget.exifInfo;

    final autoTarget = (exif.targetName?.trim().isNotEmpty == true)
        ? exif.targetName!.trim()
        : widget.objectDisplayId;
    _targetNameCtrl = TextEditingController(text: autoTarget);
    _memoCtrl = TextEditingController();
    _capturedAt = MaterialDateTimePickerField.tryParse(exif.date);
    _selectedEquipmentName =
        exif.equipment.trim().isEmpty ? null : exif.equipment.trim();
    _locationNameCtrl = TextEditingController(
      text: exif.locationName?.trim() ?? '',
    );
    _latCtrl = TextEditingController(
      text: exif.lat != null ? exif.lat!.toStringAsFixed(6) : '',
    );
    _lngCtrl = TextEditingController(
      text: exif.lng != null ? exif.lng!.toStringAsFixed(6) : '',
    );
    _stackNumCtrl = TextEditingController(
      text: exif.stackNum != null ? '${exif.stackNum}' : '',
    );
    _singleExpSecCtrl = TextEditingController(
      text: _digitsOnly(exif.singleExpSec ?? ''),
    );
    _totalExpSecCtrl = TextEditingController(
      text: MetadataFormat.minutesNumberFromDisplay(exif.exposure),
    );
    _filterCtrl = TextEditingController(text: exif.filter ?? '');
    _isoCtrl = TextEditingController(text: _digitsOnly(exif.iso));
    _fstopCtrl = TextEditingController(text: _fstopNumber(exif.fstop));
    _focalCtrl = TextEditingController(text: _digitsOnly(exif.focal));
  }

  Future<void> _loadEquipment() async {
    final repo = context.read<EquipmentRepository>();
    final list = await repo.getAll(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _equipmentList = list;
      if (_selectedEquipmentName != null &&
          !list.any((e) => e.name == _selectedEquipmentName)) {
        // EXIF 장비명이 등록 목록에 없으면 드롭다운에 임시로 유지
      }
    });
  }

  static String _digitsOnly(String raw) {
    final match = RegExp(r'[\d.]+').firstMatch(raw.replaceAll(',', ''));
    return match?.group(0) ?? '';
  }

  static String _fstopNumber(String raw) {
    final cleaned = raw.replaceFirst(RegExp(r'^[fF]/\s*'), '');
    return _digitsOnly(cleaned);
  }

  Future<void> _fetchLocationName() async {
    final lat = widget.exifInfo.lat;
    final lng = widget.exifInfo.lng;
    if (lat == null || lng == null) return;

    _isGeocoding.value = true;

    try {
      final apiKeyService = context.read<ApiKeyService>();
      final geocodingService = context.read<GeocodingService>();
      final mapsKey = await apiKeyService.get(ApiKeyType.googleMaps) ?? '';
      final result = await geocodingService.getLocationInfo(lat, lng, mapsKey);
      if (!mounted) return;
      if (result != null) {
        _geocodedLocation.value = result.locationName;
        if (_locationNameCtrl.text.trim().isEmpty) {
          _locationNameCtrl.text = result.locationName;
        }
      }
    } finally {
      if (mounted) _isGeocoding.value = false;
    }
  }

  @override
  void dispose() {
    _geocodedLocation.dispose();
    _isGeocoding.dispose();
    _showMap.dispose();
    _targetNameCtrl.dispose();
    _memoCtrl.dispose();
    _locationNameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _stackNumCtrl.dispose();
    _singleExpSecCtrl.dispose();
    _totalExpSecCtrl.dispose();
    _filterCtrl.dispose();
    _isoCtrl.dispose();
    _fstopCtrl.dispose();
    _focalCtrl.dispose();
    super.dispose();
  }

  bool _isMismatch(String targetName) {
    if (targetName.isEmpty) return false;
    final n = _norm(targetName);
    return n != _norm(widget.objectDisplayId) && n != _norm(widget.objectName);
  }

  String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  String? _v(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _onSave() async {
    final targetName = _targetNameCtrl.text.trim();
    if (targetName.isNotEmpty && _isMismatch(targetName)) {
      final proceed = await _showMismatchDialog(targetName);
      if (!proceed) return;
    }
    if (!mounted) return;

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final stackNum = int.tryParse(_stackNumCtrl.text.trim());
    final singleSec = _v(_singleExpSecCtrl.text);
    final totalExpSec =
        MetadataFormat.formatMinutesInputToExposure(_totalExpSecCtrl.text);
    final iso = _v(_isoCtrl.text);
    final fstopRaw = _v(_fstopCtrl.text);
    final focalRaw = _v(_focalCtrl.text);

    Navigator.of(context).pop(
      ConfirmedMetadata(
        targetName: _v(targetName),
        memo: _v(_memoCtrl.text),
        capturedAt: _capturedAt?.toIso8601String(),
        equipment: _selectedEquipmentName,
        locationName: _v(_locationNameCtrl.text),
        lat: lat,
        lng: lng,
        stackNum: stackNum,
        singleExpSec: singleSec == null ? null : '$singleSec초',
        totalExpSec: totalExpSec,
        filter: _v(_filterCtrl.text),
        iso: iso == null ? null : 'ISO $iso',
        fstop: fstopRaw == null ? null : 'f/$fstopRaw',
        focal: focalRaw == null ? null : '$focalRaw mm',
      ),
    );
  }

  Future<bool> _showMismatchDialog(String autoTarget) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('대상명 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MismatchRow(label: '선택한 대상', value: widget.objectDisplayId),
            const SizedBox(height: 8),
            _MismatchRow(label: '자동 인식 대상', value: autoTarget),
            const SizedBox(height: 16),
            const Text('대상이 서로 다릅니다.\n저장하시겠습니까?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openGoogleMaps() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openFullPhoto() async {
    await AppFileImage.precacheForViewer(context, widget.photoPath);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullPhotoViewerPage(photoPath: widget.photoPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exif = widget.exifInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('촬영 정보 확인')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openFullPhoto,
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppFileImage.thumbnail(
                        path: widget.photoPath,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 220,
                          color: AppColors.surface,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textSecondary,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_out_map,
                              size: 22,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '전체보기',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _RecognitionStatusBanner(exifInfo: exif),
          const SizedBox(height: 16),

          const Text(
            '대상 · 메모',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _targetNameCtrl,
            '촬영 대상명',
            widget.objectDisplayId,
          ),
          Text(
            '선택한 대상: ${widget.objectDisplayId}'
            '${widget.objectName.isNotEmpty ? ' · ${widget.objectName}' : ''}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField(_memoCtrl, '메모', '촬영 메모를 입력하세요', maxLines: 3),
          const SizedBox(height: 20),

          const Text(
            '메타 인식 정보 (수정 가능)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'EXIF에서 읽은 값을 확인하고 필요하면 수정하세요.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          MaterialDateTimePickerField(
            value: _capturedAt,
            onChanged: (value) => setState(() => _capturedAt = value),
          ),
          _buildEquipmentDropdown(),
          ValueListenableBuilder<bool>(
            valueListenable: _isGeocoding,
            builder: (context, geocoding, _) {
              return _buildTextField(
                _locationNameCtrl,
                '위치명',
                geocoding ? '위치 조회 중...' : '예: 광명시',
              );
            },
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _geocodedLocation,
            builder: (context, recommended, _) {
              if (recommended == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '추천 위치: $recommended',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _latCtrl,
                  '위도',
                  '37.493301',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  suffixText: '°',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  _lngCtrl,
                  '경도',
                  '126.872002',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  suffixText: '°',
                ),
              ),
            ],
          ),
          // 지도는 별도 State — 입력 setState와 분리해 PlatformView 재생성을 막음
          RepaintBoundary(
            child: _StableGpsMapSection(
              latController: _latCtrl,
              lngController: _lngCtrl,
              showMapListenable: _showMap,
              onOpenMaps: _openGoogleMaps,
            ),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _stackNumCtrl,
            '스택수',
            '13',
            keyboard: TextInputType.number,
            suffixText: '장',
          ),
          _buildTextField(
            _singleExpSecCtrl,
            '1장 노출시간',
            '20',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            suffixText: '초',
          ),
          IntegrationMinutesField(
            controller: _totalExpSecCtrl,
            hintText: '30',
          ),
          _buildTextField(_filterCtrl, '필터', 'LP, LRGB, None'),
          _buildTextField(
            _isoCtrl,
            'ISO',
            '200',
            keyboard: TextInputType.number,
          ),
          _buildTextField(
            _fstopCtrl,
            'F값',
            '5',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            prefixText: 'f/',
          ),
          _buildTextField(
            _focalCtrl,
            '초점거리',
            '160',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            suffixText: 'mm',
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('저장'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('취소'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEquipmentDropdown() {
    final names = <String>{
      for (final e in _equipmentList) e.name,
      ?_selectedEquipmentName,
    }.toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: _selectedEquipmentName != null &&
                names.contains(_selectedEquipmentName)
            ? _selectedEquipmentName
            : null,
        decoration: const InputDecoration(
          labelText: '장비',
          hintText: '등록된 장비를 선택하세요',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('선택 안 함'),
          ),
          ...names.map(
            (name) => DropdownMenuItem<String?>(
              value: name,
              child: Text(name),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _selectedEquipmentName = value),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? suffixText,
    String? prefixText,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffixText,
          prefixText: prefixText,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

/// 인식률 배너만 표시. 실제 값은 아래 수정 가능 필드에서 편집한다.
class _RecognitionStatusBanner extends StatelessWidget {
  const _RecognitionStatusBanner({required this.exifInfo});

  final ExifInfo exifInfo;

  bool get _hasGps => exifInfo.lat != null && exifInfo.lng != null;

  bool get _hasAnyMetadata =>
      (exifInfo.targetName?.isNotEmpty == true) ||
      exifInfo.date.isNotEmpty ||
      exifInfo.equipment.isNotEmpty ||
      _hasGps ||
      exifInfo.stackNum != null ||
      (exifInfo.singleExpSec?.isNotEmpty == true) ||
      exifInfo.exposure.isNotEmpty ||
      (exifInfo.filter?.isNotEmpty == true) ||
      exifInfo.iso.isNotEmpty ||
      exifInfo.fstop.isNotEmpty ||
      exifInfo.focal.isNotEmpty;

  (int, int) _recognitionScore() {
    const total = 10;
    var count = 0;
    if (exifInfo.targetName?.isNotEmpty == true) count++;
    if (exifInfo.date.isNotEmpty) count++;
    if (exifInfo.equipment.isNotEmpty) count++;
    if (_hasGps) count++;
    if (exifInfo.stackNum != null) count++;
    if (exifInfo.singleExpSec?.isNotEmpty == true) count++;
    if (exifInfo.exposure.isNotEmpty) count++;
    if (exifInfo.iso.isNotEmpty) count++;
    if (exifInfo.fstop.isNotEmpty) count++;
    if (exifInfo.focal.isNotEmpty) count++;
    return (count, total);
  }

  @override
  Widget build(BuildContext context) {
    final (recognized, total) = _recognitionScore();
    final hasAny = _hasAnyMetadata;

    late final String statusText;
    late final Color statusColor;
    late final IconData statusIcon;

    if (!hasAny) {
      statusText = '메타데이터를 찾을 수 없습니다. 아래 항목을 직접 입력하세요.';
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (recognized == total) {
      statusText = '자동 인식 완료 ($recognized / $total) — 값을 확인하고 수정할 수 있습니다.';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle_outline;
    } else {
      statusText = '일부 정보만 인식됨 ($recognized / $total) — 비어 있는 항목을 입력하세요.';
      statusColor = Colors.orange;
      statusIcon = Icons.info_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진 전체보기 (핀치 줌). 등록 확인·상세 입력에서 공유.
class FullPhotoViewerPage extends StatelessWidget {
  const FullPhotoViewerPage({super.key, required this.photoPath});

  final String photoPath;

  @override
  Widget build(BuildContext context) {
    final provider = AppFileImage.viewerProvider(context, photoPath);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('사진 전체보기'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 8,
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: AppColors.textSecondary,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

/// 위도/경도 입력과 지도 렌더를 부모 setState에서 분리한다.
class _StableGpsMapSection extends StatefulWidget {
  const _StableGpsMapSection({
    required this.latController,
    required this.lngController,
    required this.showMapListenable,
    required this.onOpenMaps,
  });

  final TextEditingController latController;
  final TextEditingController lngController;
  final ValueListenable<bool> showMapListenable;
  final VoidCallback onOpenMaps;

  @override
  State<_StableGpsMapSection> createState() => _StableGpsMapSectionState();
}

class _StableGpsMapSectionState extends State<_StableGpsMapSection>
    with AutomaticKeepAliveClientMixin {
  GoogleMapController? _mapController;
  Timer? _debounce;
  double? _lat;
  double? _lng;
  Marker? _marker;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.latController.addListener(_scheduleParse);
    widget.lngController.addListener(_scheduleParse);
    _parseImmediate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.latController.removeListener(_scheduleParse);
    widget.lngController.removeListener(_scheduleParse);
    _mapController = null;
    super.dispose();
  }

  void _scheduleParse() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _parseImmediate);
  }

  void _parseImmediate() {
    final lat = double.tryParse(widget.latController.text.trim());
    final lng = double.tryParse(widget.lngController.text.trim());
    final valid = lat != null && lng != null;
    if (!valid) {
      if (_lat != null || _lng != null) {
        setState(() {
          _lat = null;
          _lng = null;
          _marker = null;
        });
      }
      return;
    }
    if (_lat == lat && _lng == lng) return;
    final pos = LatLng(lat, lng);
    setState(() {
      _lat = lat;
      _lng = lng;
      _marker = Marker(
        markerId: const MarkerId('capture_location'),
        position: pos,
      );
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.showMapListenable,
      builder: (context, showMap, _) {
        if (_lat == null || _lng == null) {
          return const SizedBox.shrink();
        }
        if (!showMap) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '지도 불러오는 중…',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        final position = LatLng(_lat!, _lng!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '촬영 위치',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '지도를 탭하면 Google Maps 앱이 실행됩니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: widget.onOpenMaps,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: GoogleMap(
                    // 부모 리빌드와 무관하게 맵 인스턴스 유지
                    key: const ValueKey('metadata_review_gps_map'),
                    initialCameraPosition: CameraPosition(
                      target: position,
                      zoom: 12,
                    ),
                    markers: {
                      ?_marker,
                    },
                    onMapCreated: (controller) => _mapController = controller,
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    myLocationButtonEnabled: false,
                    liteModeEnabled: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MismatchRow extends StatelessWidget {
  const _MismatchRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
