import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/exif_info.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/google_maps_key_readiness.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/metadata_field_trace.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_overlay_service.dart';
import '../../../shared/widgets/integration_minutes_field.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../../shared/widgets/material_date_time_picker_field.dart';
import '../viewmodel/gallery_detail_view_model.dart';
import '../viewmodel/gallery_view_model.dart';
import '../viewmodel/plate_solve_view_model.dart';
import '../widgets/photo_overlay_view.dart';

@visibleForTesting
bool shouldShowManualPlateSolve(ShootingRecord record) =>
    record.photoUri != null && record.photoUri!.isNotEmpty;

// ── GalleryDetailScreen ──────────────────────────────────────────────────────

class GalleryDetailScreen extends StatefulWidget {
  const GalleryDetailScreen({super.key});

  /// 사진 상세 화면을 연다. [records]는 탐색 순서를 유지한 목록이다.
  ///
  /// [record]는 시작 페이지를 지정한다. 갤러리에서는 대표사진과 무관하게
  /// 목록의 첫 장을 넘겨 1번부터 보여 준다.
  static Future<void> open(
    BuildContext context, {
    required List<ShootingRecord> records,
    required ShootingRecord record,
  }) async {
    final galleryViewModel = context.read<GalleryViewModel>();
    final detailedRecord = await galleryViewModel.loadDetailRecord(record);
    if (!context.mounted) return;
    final hydratedRecords = records
        .map((item) => item.id == record.id ? detailedRecord : item)
        .toList(growable: false);
    final photoRecords = GalleryDetailViewModel.photoRecordsFrom(
      hydratedRecords,
    );
    final index = GalleryDetailViewModel.indexOfRecord(
      photoRecords,
      detailedRecord,
    );
    if (index < 0) return;
    final overlayService = context.read<PhotoOverlayService>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => GalleryDetailViewModel(
            records: photoRecords,
            initialIndex: index,
            overlayService: overlayService,
          ),
          child: const GalleryDetailScreen(),
        ),
      ),
    );
  }

  @override
  State<GalleryDetailScreen> createState() => _GalleryDetailScreenState();
}

class _GalleryDetailScreenState extends State<GalleryDetailScreen> {
  PageController? _pageController;
  bool _editMode = false;
  bool _pageReady = false;

  // 편집용 상태/컨트롤러
  DateTime? _capturedAt;
  late TextEditingController _equipmentCtrl;
  late TextEditingController _exposureCtrl;
  late TextEditingController _memoCtrl;
  late TextEditingController _locationNameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;

  bool _isGeocoding = false;
  bool _isSaving = false;
  bool _controllersReady = false;
  late ShootingRecord _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pageReady) {
      final detailVm = context.read<GalleryDetailViewModel>();
      _pageController = PageController(initialPage: detailVm.currentIndex);
      _record = detailVm.currentRecord;
      _initControllers();
      if (_record.exif != null) {
        MetadataFieldTrace.logExifInfo('GalleryDetail.Load', _record.exif!);
        MetadataFieldTrace.logUiValues('GalleryDetail', _record.exif!);
      }
      _pageReady = true;
    }
  }

  void _syncRecord(ShootingRecord record) {
    _record = record;
    _initControllers();
  }

  void _onPageChanged(int index) {
    if (_editMode) return;
    final detailVm = context.read<GalleryDetailViewModel>();
    detailVm.onPageChanged(index);
    setState(() => _syncRecord(detailVm.currentRecord));
  }

  void _initControllers() {
    final exif = _record.exif;
    _capturedAt = _record.capturedAt;
    if (_controllersReady) {
      _equipmentCtrl.text = exif?.equipment ?? '';
      _exposureCtrl.text = MetadataFormat.minutesNumberFromDisplay(
        exif?.exposure ?? '',
      );
      _memoCtrl.text = _record.memo;
      _locationNameCtrl.text = exif?.locationName ?? _record.location ?? '';
      _addressCtrl.text = exif?.address ?? '';
      _latCtrl.text = exif?.lat != null ? exif!.lat!.toStringAsFixed(6) : '';
      _lngCtrl.text = exif?.lng != null ? exif!.lng!.toStringAsFixed(6) : '';
      return;
    }

    _equipmentCtrl = TextEditingController(text: exif?.equipment ?? '');
    _exposureCtrl = TextEditingController(
      text: MetadataFormat.minutesNumberFromDisplay(exif?.exposure ?? ''),
    );
    _memoCtrl = TextEditingController(text: _record.memo);
    _locationNameCtrl = TextEditingController(
      text: exif?.locationName ?? _record.location ?? '',
    );
    _addressCtrl = TextEditingController(text: exif?.address ?? '');
    _latCtrl = TextEditingController(
      text: exif?.lat != null ? exif!.lat!.toStringAsFixed(6) : '',
    );
    _lngCtrl = TextEditingController(
      text: exif?.lng != null ? exif!.lng!.toStringAsFixed(6) : '',
    );
    _controllersReady = true;
  }

  @override
  void dispose() {
    _pageController?.dispose();
    if (_controllersReady) {
      _equipmentCtrl.dispose();
      _exposureCtrl.dispose();
      _memoCtrl.dispose();
      _locationNameCtrl.dispose();
      _addressCtrl.dispose();
      _latCtrl.dispose();
      _lngCtrl.dispose();
    }
    super.dispose();
  }

  void _toggleEditMode() {
    if (_editMode) {
      // 편집 취소 → 컨트롤러 초기화 (사용자 수정 데이터 보호 안 함 — 취소이므로 원복)
      _initControllers();
    }
    setState(() => _editMode = !_editMode);
  }

  Future<void> _save(BuildContext context) async {
    if (_isSaving) return;
    final viewModel = context.read<GalleryViewModel>();
    final detailVm = context.read<GalleryDetailViewModel>();
    final messenger = ScaffoldMessenger.of(context);

    final latText = _latCtrl.text.trim();
    final lngText = _lngCtrl.text.trim();
    final lat = double.tryParse(latText);
    final lng = double.tryParse(lngText);
    if ((latText.isNotEmpty && lat == null) ||
        (lngText.isNotEmpty && lng == null) ||
        (lat == null) != (lng == null) ||
        (lat != null && (lat < -90 || lat > 90)) ||
        (lng != null && (lng < -180 || lng > 180))) {
      messenger.showSnackBar(
        const SnackBar(content: Text('위도와 경도를 올바르게 입력해주세요.')),
      );
      return;
    }
    final capturedAt = _capturedAt ?? _record.capturedAt;
    final exposureText = _exposureCtrl.text.trim();
    final exposure = MetadataFormat.formatMinutesInputToExposure(exposureText);
    if (exposureText.isNotEmpty && exposure == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('적산시간을 0 이상의 분 단위 숫자로 입력해주세요.')),
      );
      return;
    }

    final existing = _record.exif;
    final updatedExif = ExifInfo(
      filename: existing?.filename ?? '',
      originalFilename: existing?.originalFilename ?? existing?.filename,
      size: existing?.size ?? '',
      date: capturedAt.toIso8601String(),
      targetName: existing?.targetName,
      focal: existing?.focal ?? '',
      fstop: existing?.fstop ?? '',
      iso: existing?.iso ?? '',
      resolution: existing?.resolution ?? '',
      equipment: _equipmentCtrl.text.trim(),
      exposure: exposure ?? '',
      lat: lat,
      lng: lng,
      locationName: _locationNameCtrl.text.trim().isEmpty
          ? null
          : _locationNameCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      stackNum: existing?.stackNum,
      singleExpSec: existing?.singleExpSec,
      filter: existing?.filter,
      imageWidth: existing?.imageWidth,
      imageHeight: existing?.imageHeight,
      ownerNameJson: existing?.ownerNameJson,
      makerNoteJson: existing?.makerNoteJson,
    );

    final updatedRecord = _record.copyWith(
      capturedAt: capturedAt,
      memo: _memoCtrl.text.trim(),
      location: _locationNameCtrl.text.trim().isEmpty
          ? null
          : _locationNameCtrl.text.trim(),
      clearLocation: _locationNameCtrl.text.trim().isEmpty,
      exif: updatedExif,
    );

    setState(() => _isSaving = true);
    final saved = await viewModel.updateRecord(updatedRecord);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!saved) {
      messenger.showSnackBar(
        const SnackBar(content: Text('저장하지 못했습니다. 기존 값은 유지됩니다.')),
      );
      return;
    }

    detailVm.updateRecord(updatedRecord);
    setState(() {
      _syncRecord(updatedRecord);
      _editMode = false;
    });
    messenger.showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
  }

  Future<void> _reverseGeocode(BuildContext context) async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final messenger = ScaffoldMessenger.of(context);

    if (lat == null || lng == null) {
      messenger.showSnackBar(const SnackBar(content: Text('위도/경도를 먼저 입력하세요.')));
      return;
    }

    final geocodingService = context.read<GeocodingService>();

    setState(() => _isGeocoding = true);

    try {
      final result = await geocodingService.getLocationInfo(lat, lng);
      if (!mounted) return;
      if (result != null) {
        _locationNameCtrl.text = result.locationName;
        _addressCtrl.text = result.address;
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('위치 정보를 찾을 수 없습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Geocoding 오류가 발생했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  void _onMapLocationChanged(double lat, double lng) {
    setState(() {
      _latCtrl.text = lat.toStringAsFixed(6);
      _lngCtrl.text = lng.toStringAsFixed(6);
    });
  }

  @override
  Widget build(BuildContext context) {
    final galleryVm = context.watch<GalleryViewModel>();
    final detailVm = context.watch<GalleryDetailViewModel>();
    _record = detailVm.currentRecord;
    final obj = galleryVm.catalogObjectFor(_record.celestialObjectId);
    final pageController = _pageController;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(obj?.displayId ?? _record.celestialObjectId),
            if (detailVm.positionLabel != null)
              Text(
                detailVm.positionLabel!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (!_editMode) ...[
            IconButton(
              icon: Icon(
                _record.isFavorite ? Icons.star : Icons.star_border,
                color: _record.isFavorite ? Colors.amber : null,
              ),
              tooltip: _record.isFavorite ? '즐겨찾기 해제' : '즐겨찾기',
              onPressed: () => _toggleFavorite(context, galleryVm, detailVm),
            ),
            IconButton(
              icon: Icon(
                _record.isRepresentative
                    ? Icons.photo_album
                    : Icons.photo_album_outlined,
                color: _record.isRepresentative ? AppColors.ic : null,
              ),
              tooltip: '대표사진으로 설정',
              onPressed: _record.photoUri == null || _record.photoUri!.isEmpty
                  ? null
                  : () => _setRepresentative(context, galleryVm, detailVm),
            ),
          ],
          if (_editMode) ...[
            TextButton(
              onPressed: _isSaving ? null : () => _save(context),
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '저장',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '편집 취소',
              onPressed: _isSaving ? null : _toggleEditMode,
            ),
          ] else
            PopupMenuButton<_Action>(
              onSelected: (action) => _handleAction(context, action, galleryVm),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _Action.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('기록 수정'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _Action.delete,
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    title: Text(
                      '기록 삭제',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: pageController == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: pageController,
              physics: _editMode
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              itemCount: detailVm.records.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final record = detailVm.records[index];
                final recordObj = galleryVm.catalogObjectFor(
                  record.celestialObjectId,
                );
                if (_editMode && index == detailVm.currentIndex) {
                  return _EditBody(
                    record: record,
                    obj: recordObj,
                    capturedAt: _capturedAt,
                    onCapturedAtChanged: (value) {
                      setState(() => _capturedAt = value);
                    },
                    equipmentCtrl: _equipmentCtrl,
                    exposureCtrl: _exposureCtrl,
                    memoCtrl: _memoCtrl,
                    locationNameCtrl: _locationNameCtrl,
                    addressCtrl: _addressCtrl,
                    latCtrl: _latCtrl,
                    lngCtrl: _lngCtrl,
                    isGeocoding: _isGeocoding,
                    onReverseGeocode: () => _reverseGeocode(context),
                    onChangeTarget: () =>
                        _showChangeTargetSheet(context, galleryVm),
                    onMapLocationChanged: _onMapLocationChanged,
                  );
                }
                return _ViewBody(
                  record: record,
                  obj: recordObj,
                  onRunPlateSolve: () => _runPlateSolveFor(record),
                );
              },
            ),
    );
  }

  void _handleAction(
    BuildContext context,
    _Action action,
    GalleryViewModel viewModel,
  ) {
    switch (action) {
      case _Action.edit:
        _toggleEditMode();
      case _Action.delete:
        _showDeleteDialog(context, viewModel);
    }
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    GalleryViewModel galleryVm,
    GalleryDetailViewModel detailVm,
  ) async {
    final current = detailVm.currentRecord;
    await galleryVm.toggleFavorite(current);
    final updated = current.copyWith(isFavorite: !current.isFavorite);
    detailVm.updateRecord(updated);
    setState(() => _syncRecord(updated));
  }

  Future<void> _setRepresentative(
    BuildContext context,
    GalleryViewModel galleryVm,
    GalleryDetailViewModel detailVm,
  ) async {
    final current = detailVm.currentRecord;
    await galleryVm.setRepresentativePhoto(current);
    for (final record in detailVm.records) {
      if (record.celestialObjectId != current.celestialObjectId) continue;
      detailVm.updateRecord(
        record.copyWith(isRepresentative: record.id == current.id),
      );
    }
    setState(() => _syncRecord(detailVm.currentRecord));
  }

  /// [record]에 대해 Plate Solve를 실행하고, 완료되면 상세 화면 상태를 갱신한다.
  Future<void> _runPlateSolveFor(ShootingRecord record) async {
    final plateSolveVm = context.read<PlateSolveViewModel>();
    final galleryVm = context.read<GalleryViewModel>();
    final detailVm = context.read<GalleryDetailViewModel>();

    await plateSolveVm.solve(record);
    if (!mounted) return;

    final updated = galleryVm.recordForId(record.id);
    if (updated == null) return;
    detailVm.updateRecord(updated);
    if (updated.id == _record.id) {
      setState(() => _syncRecord(updated));
    }
  }

  void _showChangeTargetSheet(
    BuildContext context,
    GalleryViewModel viewModel,
  ) {
    final searchController = TextEditingController();
    var filtered = viewModel.allCatalogObjects;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (_, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '대상 검색 (예: M42, Orion)',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (query) {
                          final q = query.toLowerCase();
                          setSheetState(() {
                            filtered = viewModel.allCatalogObjects
                                .where(
                                  (o) =>
                                      o.displayId.toLowerCase().contains(q) ||
                                      o.name.toLowerCase().contains(q),
                                )
                                .toList();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final obj = filtered[index];
                          final isCurrent = obj.id == _record.celestialObjectId;
                          return ListTile(
                            title: Text(obj.displayId),
                            subtitle: Text(
                              obj.name,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            trailing: isCurrent
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.messier,
                                  )
                                : null,
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              final detailVm = context
                                  .read<GalleryDetailViewModel>();
                              await viewModel.updateTarget(_record, obj.id);
                              final updated = _record.copyWith(
                                celestialObjectId: obj.id,
                              );
                              if (mounted) {
                                detailVm.updateRecord(updated);
                                setState(() => _syncRecord(updated));
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, GalleryViewModel viewModel) {
    final parentNavigator = Navigator.of(context);
    final detailVm = context.read<GalleryDetailViewModel>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('이 촬영 기록을 삭제하시겠습니까?\n사진 파일도 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final deletedId = _record.id;
              await viewModel.deleteRecord(_record);
              if (!mounted) return;
              final remaining = detailVm.removeRecord(deletedId);
              if (remaining == 0) {
                parentNavigator.pop();
                return;
              }
              _pageController?.jumpToPage(detailVm.currentIndex);
              setState(() => _syncRecord(detailVm.currentRecord));
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

// ── 보기 모드 (원본 사진 우선 + 상세정보 Bottom Sheet) ───────────────────────

class _ViewBody extends StatelessWidget {
  const _ViewBody({required this.record, this.obj, this.onRunPlateSolve});

  final ShootingRecord record;
  final dynamic obj;
  final VoidCallback? onRunPlateSolve;

  String _formatDateTime(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)}  ${p(dt.hour)}:${p(dt.minute)}';
  }

  Future<void> _showDetailsSheet(BuildContext context) {
    final detailVm = context.read<GalleryDetailViewModel>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return ChangeNotifierProvider.value(
          value: detailVm,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '상세정보',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: _detailInfoChildren(context),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _detailInfoChildren(BuildContext context) {
    return [
      _InfoCard(
        icon: Icons.stars_outlined,
        title: '촬영 대상',
        content: obj != null
            ? '${obj.displayId}  ${obj.name}\n${obj.displayType} · ${obj.displayConstellation}'
            : record.celestialObjectId,
      ),
      const SizedBox(height: 12),
      _InfoCard(
        icon: Icons.calendar_today_outlined,
        title: '촬영일시',
        content: _formatDateTime(record.capturedAt),
      ),
      const SizedBox(height: 12),
      _InfoCard(
        key: const Key('gallery-detail-equipment'),
        icon: Icons.camera_alt_outlined,
        title: '촬영 장비',
        content: record.exif?.equipment.trim().isNotEmpty == true
            ? record.exif!.equipment
            : '미입력',
      ),
      const SizedBox(height: 12),
      _MultiFieldCard(
        key: const Key('gallery-detail-integration'),
        icon: Icons.layers_outlined,
        title: '스택 / 노출 정보',
        rows: [
          _FieldRow(
            label: '적산시간',
            value: record.exif?.exposure.trim().isNotEmpty == true
                ? record.exif!.exposure
                : '미입력',
          ),
          if (record.exif?.stackNum != null)
            _FieldRow(label: '스택 수', value: '${record.exif!.stackNum!}장'),
          if (record.exif?.singleExpSec?.isNotEmpty == true)
            _FieldRow(label: '1장 노출', value: record.exif!.singleExpSec!),
          if (record.exif?.filter?.isNotEmpty == true)
            _FieldRow(label: '필터', value: record.exif!.filter!),
        ],
      ),
      if ((record.exif?.iso.isNotEmpty == true) ||
          (record.exif?.fstop.isNotEmpty == true) ||
          (record.exif?.focal.isNotEmpty == true)) ...[
        const SizedBox(height: 12),
        _MultiFieldCard(
          icon: Icons.settings_outlined,
          title: '카메라 설정',
          rows: [
            if (record.exif?.iso.isNotEmpty == true)
              _FieldRow(label: 'ISO', value: record.exif!.iso),
            if (record.exif?.fstop.isNotEmpty == true)
              _FieldRow(label: '조리개', value: record.exif!.fstop),
            if (record.exif?.focal.isNotEmpty == true)
              _FieldRow(label: '초점거리', value: record.exif!.focal),
          ],
        ),
      ],
      if ((record.exif?.resolution.isNotEmpty == true) ||
          (record.exif?.size.isNotEmpty == true)) ...[
        const SizedBox(height: 12),
        _MultiFieldCard(
          icon: Icons.photo_size_select_actual_outlined,
          title: '이미지 정보',
          rows: [
            if (record.exif?.resolution.isNotEmpty == true)
              _FieldRow(label: '해상도', value: record.exif!.resolution),
            if (record.exif?.size.isNotEmpty == true)
              _FieldRow(label: '파일 크기', value: record.exif!.size),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _InfoCard(
        icon: Icons.notes_outlined,
        title: '메모',
        content: record.memo.isEmpty ? '(없음)' : record.memo,
      ),
      if (shouldShowManualPlateSolve(record) && onRunPlateSolve != null) ...[
        const SizedBox(height: 12),
        GalleryPlateSolveSection(record: record, onRun: onRunPlateSolve!),
      ],
      const SizedBox(height: 12),
      if (record.exif?.lat != null && record.exif?.lng != null)
        _LocationMapCard(
          lat: record.exif!.lat!,
          lng: record.exif!.lng!,
          locationName: record.exif?.locationName ?? record.location,
          address: record.exif?.address,
        )
      else
        _NoLocationCard(
          key: const Key('gallery-detail-location'),
          locationName: record.exif?.locationName ?? record.location,
          address: record.exif?.address,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final detailVm = context.watch<GalleryDetailViewModel>();
    // Overlay는 ON일 때만 계산한다 — build에서 ensureOverlayLoaded 호출 금지.

    return Column(
      children: [
        Expanded(
          child: _PhotoSection(
            photoUri: record.galleryPreviewUri,
            overlay: detailVm.overlayFor(record.id),
            isOverlayLoading: detailVm.isOverlayLoadingFor(record.id),
            overlayEnabled: detailVm.overlayEnabled,
            showTarget: detailVm.showTarget,
            showNearby: detailVm.showNearby,
            onToggleOverlayEnabled: detailVm.toggleOverlayEnabled,
            onToggleShowTarget: detailVm.toggleShowTarget,
            onToggleShowNearby: detailVm.toggleShowNearby,
            onRequestOverlayLoad: detailVm.requestOverlayForCurrent,
            fillViewport: true,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => unawaited(_showDetailsSheet(context)),
                icon: const Icon(Icons.info_outline),
                label: const Text('상세정보'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Plate Solve (WCS) ────────────────────────────────────────────────────────

@visibleForTesting
class GalleryPlateSolveSection extends StatelessWidget {
  const GalleryPlateSolveSection({
    super.key,
    required this.record,
    required this.onRun,
  });

  final ShootingRecord record;
  final VoidCallback onRun;

  String _formatDateTime(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runState = context.watch<PlateSolveViewModel>().stateFor(record.id);
    // BottomSheet가 열린 뒤 record snapshot은 바뀌지 않을 수 있으므로
    // 실행 결과는 ViewModel의 최신 run state를 우선한다.
    final solved = runState.result ?? record.plateSolve;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.explore_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Plate Solve (WCS)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (runState.isRunning)
            _PlateSolveProgressRow(
              key: const Key('plate-solve-processing'),
              message: runState.message ?? 'Plate Solving...',
            )
          else if (solved != null && solved.success)
            _PlateSolveSuccessBody(
              result: solved,
              formatDateTime: _formatDateTime,
              onRun: onRun,
            )
          else if (solved != null && !solved.success)
            _PlateSolveFailureBody(result: solved, onRun: onRun)
          else
            _PlateSolveIdleBody(onRun: onRun),
        ],
      ),
    );
  }
}

class _PlateSolveProgressRow extends StatelessWidget {
  const _PlateSolveProgressRow({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.messier,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.messier, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PlateSolveSuccessBody extends StatelessWidget {
  const _PlateSolveSuccessBody({
    required this.result,
    required this.formatDateTime,
    required this.onRun,
  });

  final PlateSolveResult result;
  final String Function(DateTime) formatDateTime;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldRow(
          label: '중심 RA',
          value: result.centerRa != null
              ? '${result.centerRa!.toStringAsFixed(4)}°'
              : '-',
        ).build(context),
        _FieldRow(
          label: '중심 DEC',
          value: result.centerDec != null
              ? '${result.centerDec!.toStringAsFixed(4)}°'
              : '-',
        ).build(context),
        _FieldRow(
          label: '회전각',
          value: result.rotation != null
              ? '${result.rotation!.toStringAsFixed(2)}°'
              : '-',
        ).build(context),
        _FieldRow(
          label: '픽셀 스케일',
          value: result.pixelScale != null
              ? '${result.pixelScale!.toStringAsFixed(3)}"/px'
              : '-',
        ).build(context),
        _FieldRow(
          label: 'FOV',
          value: (result.fovWidth != null && result.fovHeight != null)
              ? '${result.fovWidth!.toStringAsFixed(2)}° × '
                    '${result.fovHeight!.toStringAsFixed(2)}°'
              : '-',
        ).build(context),
        _FieldRow(label: 'Solver', value: result.solver ?? '-').build(context),
        if (result.solveMode != null)
          _FieldRow(
            label: '모드',
            value: result.solveMode == PlateSolveMode.targeted
                ? 'Targeted${result.targetObject != null ? ' (${result.targetObject})' : ''}'
                : 'Blind',
          ).build(context),
        if (result.solveTimeMs != null)
          _FieldRow(
            label: '소요 시간',
            value: result.solveTimeMs! >= 1000
                ? '${(result.solveTimeMs! / 1000).toStringAsFixed(1)}초'
                : '${result.solveTimeMs}ms',
          ).build(context),
        if (result.solvedAt != null)
          _FieldRow(
            label: '완료 시각',
            value: formatDateTime(result.solvedAt!),
          ).build(context),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRun,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Plate Solve 다시 실행'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.messier,
              side: BorderSide(color: AppColors.messier.withAlpha(120)),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlateSolveFailureBody extends StatelessWidget {
  const _PlateSolveFailureBody({required this.result, required this.onRun});

  final PlateSolveResult result;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                result.errorMessage ?? 'Plate Solve에 실패했습니다.',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRun,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Plate Solve 다시 실행'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.messier,
              side: BorderSide(color: AppColors.messier.withAlpha(120)),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlateSolveIdleBody extends StatelessWidget {
  const _PlateSolveIdleBody({required this.onRun});

  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '이 사진은 아직 Plate Solve를 수행하지 않았습니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRun,
            icon: const Icon(Icons.explore_outlined, size: 16),
            label: const Text('Plate Solve 실행'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.messier,
              side: BorderSide(color: AppColors.messier.withAlpha(120)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 편집 모드 ────────────────────────────────────────────────────────────────

class _EditBody extends StatelessWidget {
  const _EditBody({
    required this.record,
    required this.obj,
    required this.capturedAt,
    required this.onCapturedAtChanged,
    required this.equipmentCtrl,
    required this.exposureCtrl,
    required this.memoCtrl,
    required this.locationNameCtrl,
    required this.addressCtrl,
    required this.latCtrl,
    required this.lngCtrl,
    required this.isGeocoding,
    required this.onReverseGeocode,
    required this.onChangeTarget,
    required this.onMapLocationChanged,
  });

  final ShootingRecord record;
  final dynamic obj;
  final DateTime? capturedAt;
  final ValueChanged<DateTime?> onCapturedAtChanged;
  final TextEditingController equipmentCtrl;
  final TextEditingController exposureCtrl;
  final TextEditingController memoCtrl;
  final TextEditingController locationNameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final bool isGeocoding;
  final VoidCallback onReverseGeocode;
  final VoidCallback onChangeTarget;
  final void Function(double lat, double lng) onMapLocationChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PhotoSection(photoUri: record.galleryPreviewUri),
        const SizedBox(height: 16),

        // 편집 안내 배너
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.messier.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.messier.withAlpha(80)),
          ),
          child: const Row(
            children: [
              Icon(Icons.edit_outlined, size: 14, color: AppColors.messier),
              SizedBox(width: 8),
              Text(
                '편집 모드 – 수정 후 우측 상단 [저장]을 누르세요.',
                style: TextStyle(color: AppColors.messier, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 촬영 대상
        _EditSection(title: '촬영 대상'),
        _TargetEditRow(
          obj: obj,
          celestialObjectId: record.celestialObjectId,
          onChangeTarget: onChangeTarget,
        ),
        const SizedBox(height: 16),

        // 촬영일시
        MaterialDateTimePickerField(
          value: capturedAt,
          onChanged: onCapturedAtChanged,
          hintText: '날짜와 시간을 선택하세요',
        ),

        // 장비명
        _EditSection(title: '장비명'),
        _EditField(controller: equipmentCtrl, hint: '예: Seestar S30 Pro'),
        const SizedBox(height: 16),

        // 총 적분시간
        IntegrationMinutesField(controller: exposureCtrl, hintText: '30'),

        // 메모
        _EditSection(title: '메모'),
        _EditField(controller: memoCtrl, hint: '메모를 입력하세요', maxLines: 3),
        const SizedBox(height: 16),

        // 촬영지명
        _EditSection(title: '촬영지명'),
        _EditField(controller: locationNameCtrl, hint: '예: 탄도항, 안반데기'),
        const SizedBox(height: 16),

        // 주소 검색 + 광해지도 즐겨찾기
        _EditSection(title: '주소'),
        _EditAddressSearchSection(
          locationNameCtrl: locationNameCtrl,
          addressCtrl: addressCtrl,
          latCtrl: latCtrl,
          lngCtrl: lngCtrl,
        ),
        const SizedBox(height: 16),

        // 좌표
        _EditSection(title: '좌표'),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '위도',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _EditField(
                    controller: latCtrl,
                    hint: '37.000000',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '경도',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _EditField(
                    controller: lngCtrl,
                    hint: '126.000000',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isGeocoding ? null : onReverseGeocode,
            icon: isGeocoding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : const Icon(Icons.location_searching_outlined, size: 16),
            label: Text(isGeocoding ? '조회 중...' : '좌표로 촬영지명 자동 조회'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: BorderSide(color: AppColors.textSecondary.withAlpha(80)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 지도 (좌표 있을 때)
        _MapEditSection(
          latCtrl: latCtrl,
          lngCtrl: lngCtrl,
          onLocationChanged: onMapLocationChanged,
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── 주소 검색 + 즐겨찾기 ─────────────────────────────────────────────────────

class _EditAddressSearchSection extends StatefulWidget {
  const _EditAddressSearchSection({
    required this.locationNameCtrl,
    required this.addressCtrl,
    required this.latCtrl,
    required this.lngCtrl,
  });

  final TextEditingController locationNameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;

  @override
  State<_EditAddressSearchSection> createState() =>
      _EditAddressSearchSectionState();
}

class _EditAddressSearchSectionState extends State<_EditAddressSearchSection> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  var _suppressSearch = false;
  var _isSearching = false;
  String? _searchError;
  List<LocationSearchSuggestion> _suggestions = const [];
  List<ObservationSite> _favorites = const [];
  var _favoritesLoading = true;
  String? _selectedFavoriteId;
  var _favoritesMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchTextChanged);
    // 기존 주소가 있으면 검색창에 표시
    final existing = widget.addressCtrl.text.trim();
    if (existing.isNotEmpty) {
      _suppressSearch = true;
      _searchCtrl.text = existing;
      _suppressSearch = false;
    }
    unawaited(_loadFavorites());
  }

  Future<void> _loadFavorites() async {
    try {
      final list = (await context.read<ObservationSiteRepository>().list())
          .where((site) => site.isFavorite)
          .toList();
      if (!mounted) return;
      setState(() {
        _favorites = list;
        _favoritesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _favorites = const [];
        _favoritesLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchTextChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (_suppressSearch) return;
    _searchDebounce?.cancel();
    final query = _searchCtrl.text.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty || _isSearching || _searchError != null) {
        setState(() {
          _suggestions = const [];
          _isSearching = false;
          _searchError = null;
        });
      }
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_fetchSuggestions(query)),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await context
          .read<GeocodingService>()
          .autocompleteLocations(query);
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _isSearching = false;
        _suggestions = results;
        _searchError = results.isEmpty ? '검색 결과가 없습니다.' : null;
      });
    } catch (_) {
      if (!mounted || _searchCtrl.text.trim() != query) return;
      setState(() {
        _isSearching = false;
        _suggestions = const [];
        _searchError = '주소 검색에 실패했습니다.';
      });
    }
  }

  Future<void> _selectSuggestion(LocationSearchSuggestion suggestion) async {
    _suppressSearch = true;
    _searchCtrl.text = suggestion.mainText;
    _suppressSearch = false;
    _searchFocus.unfocus();
    setState(() {
      _suggestions = const [];
      _searchError = null;
      _isSearching = true;
      _selectedFavoriteId = null;
    });

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
        result = await context.read<GeocodingService>().getPlaceDetails(
          suggestion.placeId!,
        );
      }

      if (!mounted) return;
      if (result == null) {
        setState(() {
          _isSearching = false;
          _searchError = '장소 정보를 불러오지 못했습니다.';
        });
        return;
      }

      final label = result.displayLabel;
      final cleaned = GeocodingService.cleanDisplayAddress(
        result.formattedAddress,
      );
      widget.addressCtrl.text = cleaned.isNotEmpty
          ? cleaned
          : result.formattedAddress;
      if (widget.locationNameCtrl.text.trim().isEmpty) {
        widget.locationNameCtrl.text =
            result.placeName?.trim().isNotEmpty == true
            ? result.placeName!.trim()
            : label;
      }
      widget.latCtrl.text = result.latitude.toStringAsFixed(6);
      widget.lngCtrl.text = result.longitude.toStringAsFixed(6);
      _suppressSearch = true;
      _searchCtrl.text = widget.addressCtrl.text;
      _suppressSearch = false;
      setState(() => _isSearching = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = '장소 정보를 불러오지 못했습니다.';
      });
    }
  }

  void _applyFavorite(ObservationSite favorite) {
    _searchFocus.unfocus();
    setState(() {
      _suggestions = const [];
      _searchError = null;
      _selectedFavoriteId = favorite.id;
      _favoritesMenuOpen = false;
    });
    widget.locationNameCtrl.text = favorite.name;
    widget.addressCtrl.text = favorite.name;
    widget.latCtrl.text = favorite.latitude.toStringAsFixed(6);
    widget.lngCtrl.text = favorite.longitude.toStringAsFixed(6);
    _suppressSearch = true;
    _searchCtrl.text = favorite.name;
    _suppressSearch = false;
  }

  void _toggleFavoritesMenu() {
    _searchFocus.unfocus();
    setState(() {
      _favoritesMenuOpen = !_favoritesMenuOpen;
      if (_favoritesMenuOpen) {
        _suggestions = const [];
        _searchError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();
    final showSuggestions =
        !_favoritesMenuOpen &&
        query.length >= 2 &&
        (_isSearching || _suggestions.isNotEmpty || _searchError != null);
    final selectedFavorite = _selectedFavoriteId == null
        ? null
        : _favorites.where((f) => f.id == _selectedFavoriteId).firstOrNull;
    final menuMaxHeight = math.min(
      220.0,
      MediaQuery.sizeOf(context).height * 0.28,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_favoritesLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_favorites.isNotEmpty) ...[
          // 선택창 너비와 동일한 인라인 드롭다운 (시스템 Overlay 미사용)
          InkWell(
            onTap: _toggleFavoritesMenu,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              isFocused: _favoritesMenuOpen,
              decoration: InputDecoration(
                labelText: '광해지도 즐겨찾기',
                hintText: '자주 가는 촬영지 선택',
                prefixIcon: const Icon(Icons.star_outline, size: 20),
                suffixIcon: Icon(
                  _favoritesMenuOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 22,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              child: Text(
                selectedFavorite?.name ?? '자주 가는 촬영지 선택',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selectedFavorite == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (_favoritesMenuOpen) ...[
            const SizedBox(height: 4),
            Material(
              color: AppColors.surface,
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: menuMaxHeight),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _favorites.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0x14FFFFFF),
                  ),
                  itemBuilder: (context, index) {
                    final fav = _favorites[index];
                    final selected = fav.id == _selectedFavoriteId;
                    return InkWell(
                      onTap: () => _applyFavorite(fav),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected ? Icons.star : Icons.star_outline,
                              size: 18,
                              color: selected
                                  ? AppColors.solar
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                fav.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check,
                                size: 16,
                                color: AppColors.messier,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '선택하면 촬영지명·주소·좌표가 자동으로 채워집니다.',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final q = value.trim();
            if (q.length >= 2) unawaited(_fetchSuggestions(q));
          },
          onTap: () {
            if (_favoritesMenuOpen) {
              setState(() => _favoritesMenuOpen = false);
            }
          },
          decoration: InputDecoration(
            labelText: '주소 검색',
            hintText: '예: 광명시, 설악산',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _suppressSearch = true;
                            _searchCtrl.clear();
                            _suppressSearch = false;
                            setState(() {
                              _suggestions = const [];
                              _searchError = null;
                              _isSearching = false;
                            });
                            _searchFocus.requestFocus();
                          },
                        )
                      : null),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          onChanged: (value) {
            // 직접 입력한 검색어를 주소 필드로도 유지
            widget.addressCtrl.text = value.trim();
            if (_favoritesMenuOpen) {
              setState(() => _favoritesMenuOpen = false);
            }
          },
        ),
        if (showSuggestions) ...[
          const SizedBox(height: 4),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                if (_searchError != null && _suggestions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ..._suggestions.map(
                    (s) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(
                        s.mainText,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: s.secondaryText == null
                          ? null
                          : Text(
                              GeocodingService.cleanDisplayAddress(
                                s.secondaryText!,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                      onTap: () => unawaited(_selectSuggestion(s)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── 촬영 대상 편집 행 ────────────────────────────────────────────────────────

class _TargetEditRow extends StatelessWidget {
  const _TargetEditRow({
    required this.obj,
    required this.celestialObjectId,
    required this.onChangeTarget,
  });

  final dynamic obj;
  final String celestialObjectId;
  final VoidCallback onChangeTarget;

  @override
  Widget build(BuildContext context) {
    final displayText = obj != null
        ? '${obj.displayId}  ${obj.name}'
        : celestialObjectId;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayText,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onChangeTarget,
          icon: const Icon(Icons.swap_horiz, size: 16),
          label: const Text('변경'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.messier,
            side: BorderSide(color: AppColors.messier.withAlpha(120)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// ── 지도 편집 위젯 ────────────────────────────────────────────────────────────

class _MapEditSection extends StatefulWidget {
  const _MapEditSection({
    required this.latCtrl,
    required this.lngCtrl,
    required this.onLocationChanged,
  });

  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final void Function(double lat, double lng) onLocationChanged;

  @override
  State<_MapEditSection> createState() => _MapEditSectionState();
}

class _MapEditSectionState extends State<_MapEditSection> {
  GoogleMapController? _mapController;
  LatLng? _markerPosition;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _updateMarkerFromControllers();
    widget.latCtrl.addListener(_onControllerChanged);
    widget.lngCtrl.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.latCtrl.removeListener(_onControllerChanged);
    widget.lngCtrl.removeListener(_onControllerChanged);
    _mapController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final lat = double.tryParse(widget.latCtrl.text);
    final lng = double.tryParse(widget.lngCtrl.text);
    if (lat != null && lng != null) {
      final newPos = LatLng(lat, lng);
      if (_markerPosition != newPos) {
        setState(() => _markerPosition = newPos);
        if (_mapReady) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
        }
      }
    }
  }

  void _updateMarkerFromControllers() {
    final lat = double.tryParse(widget.latCtrl.text);
    final lng = double.tryParse(widget.lngCtrl.text);
    if (lat != null && lng != null) {
      _markerPosition = LatLng(lat, lng);
    }
  }

  void _onMapTap(LatLng pos) {
    setState(() => _markerPosition = pos);
    widget.onLocationChanged(pos.latitude, pos.longitude);
  }

  void _onMarkerDragEnd(LatLng pos) {
    setState(() => _markerPosition = pos);
    widget.onLocationChanged(pos.latitude, pos.longitude);
  }

  @override
  Widget build(BuildContext context) {
    if (_markerPosition == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.map_outlined, size: 16, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '위도/경도를 입력하면 지도에서 위치를 확인하고 수정할 수 있습니다.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _EditSection(title: '지도에서 위치 수정'),
        const SizedBox(height: 4),
        const Text(
          '지도를 탭하거나 핀을 드래그하여 위치를 수정하세요. 확대·축소로 넓은 범위도 확인할 수 있습니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 220,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _markerPosition!,
                zoom: 12,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('edit_location'),
                  position: _markerPosition!,
                  draggable: true,
                  onDragEnd: _onMarkerDragEnd,
                ),
              },
              onTap: _onMapTap,
              onMapCreated: (controller) {
                _mapController = controller;
                setState(() => _mapReady = true);
              },
              // 부모 ListView가 드래그를 가로채지 않도록 지도가 제스처를 우선 점유
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              zoomControlsEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditSection extends StatelessWidget {
  const _EditSection({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.hint,
    this.keyboard,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

// ── _PhotoSection ────────────────────────────────────────────────────────────

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photoUri,
    this.overlay,
    this.isOverlayLoading = false,
    this.overlayEnabled = true,
    this.showTarget = true,
    this.showNearby = true,
    this.onToggleOverlayEnabled,
    this.onToggleShowTarget,
    this.onToggleShowNearby,
    this.onRequestOverlayLoad,
    this.fillViewport = false,
  });

  final String? photoUri;
  final PhotoOverlayResult? overlay;
  final bool isOverlayLoading;
  final bool overlayEnabled;
  final bool showTarget;
  final bool showNearby;
  final VoidCallback? onToggleOverlayEnabled;
  final VoidCallback? onToggleShowTarget;
  final VoidCallback? onToggleShowNearby;
  final VoidCallback? onRequestOverlayLoad;
  final bool fillViewport;

  bool get _hasOverlayControls => onToggleOverlayEnabled != null;
  bool get _hasOverlayData => overlay != null && overlay!.isAvailable;

  @override
  Widget build(BuildContext context) {
    if (photoUri == null) {
      return Container(
        height: fillViewport ? double.infinity : 200,
        color: AppColors.surface,
        child: const Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 64,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    final showOverlay = overlayEnabled && _hasOverlayData;
    final image = showOverlay
        ? PhotoOverlayView(
            photoPath: photoUri!,
            imageWidth: overlay!.imageWidth,
            imageHeight: overlay!.imageHeight,
            objects: overlay!.objects,
            showTarget: showTarget,
            showNearby: showNearby,
          )
        : AppFileImage(
            path: photoUri!,
            fit: BoxFit.contain,
            memCacheWidth: fillViewport ? 2048 : 1600,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(
              height: fillViewport ? null : 200,
              color: AppColors.surface,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );

    return Container(
      constraints: fillViewport
          ? const BoxConstraints.expand()
          : const BoxConstraints(maxHeight: 280),
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: InteractiveViewer(maxScale: 6, child: Center(child: image)),
          ),
          if (_hasOverlayControls)
            Positioned(
              top: 8,
              right: 8,
              child: _OverlayControlButton(
                isLoading: isOverlayLoading,
                hasData: _hasOverlayData,
                overlayEnabled: overlayEnabled,
                showTarget: showTarget,
                showNearby: showNearby,
                onToggleOverlayEnabled: onToggleOverlayEnabled!,
                onToggleShowTarget: onToggleShowTarget!,
                onToggleShowNearby: onToggleShowNearby!,
                onOpenMenu: onRequestOverlayLoad,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Overlay ON/OFF 옵션 버튼 ──────────────────────────────────────────────────

class _OverlayControlButton extends StatelessWidget {
  const _OverlayControlButton({
    required this.isLoading,
    required this.hasData,
    required this.overlayEnabled,
    required this.showTarget,
    required this.showNearby,
    required this.onToggleOverlayEnabled,
    required this.onToggleShowTarget,
    required this.onToggleShowNearby,
    this.onOpenMenu,
  });

  final bool isLoading;
  final bool hasData;
  final bool overlayEnabled;
  final bool showTarget;
  final bool showNearby;
  final VoidCallback onToggleOverlayEnabled;
  final VoidCallback onToggleShowTarget;
  final VoidCallback onToggleShowNearby;
  final VoidCallback? onOpenMenu;

  static const _popupWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final active = overlayEnabled && hasData;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        iconSize: 20,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                active ? Icons.layers : Icons.layers_outlined,
                color: active ? AppColors.solar : Colors.white,
              ),
        tooltip: '천체 Overlay 옵션',
        onPressed: () {
          onOpenMenu?.call();
          _openOverlayPopup(context);
        },
      ),
    );
  }

  void _openOverlayPopup(BuildContext context) {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;

    final buttonTopLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final buttonSize = button.size;
    final screen = overlay.size;

    // 버튼 아래·왼쪽으로 붙임 (우측 상단 버튼 기준)
    var left = buttonTopLeft.dx + buttonSize.width - _popupWidth;
    var top = buttonTopLeft.dy + buttonSize.height + 4;
    left = left.clamp(8.0, math.max(8.0, screen.width - _popupWidth - 8));
    final estimatedHeight = hasData ? 200.0 : 220.0;
    if (top + estimatedHeight > screen.height - 8) {
      top = buttonTopLeft.dy - estimatedHeight - 4;
    }
    top = top.clamp(8.0, math.max(8.0, screen.height - estimatedHeight - 8));

    var enabled = overlayEnabled;
    var target = showTarget;
    var nearby = showNearby;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: _popupWidth,
              child: Material(
                color: AppColors.surface,
                elevation: 8,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (_, setPopupState) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 2, 12, 6),
                            child: Text(
                              '천체 Overlay',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          SwitchListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: const Text(
                              'Overlay 표시',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: !hasData
                                ? const Text(
                                    'Plate Solve 결과가 없어 표시할 수 없습니다.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  )
                                : null,
                            value: enabled,
                            activeThumbColor: AppColors.solar,
                            onChanged: (_) {
                              onToggleOverlayEnabled();
                              setPopupState(() => enabled = !enabled);
                            },
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: const Text(
                              '촬영 대상 표시',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            value: target,
                            activeColor: AppColors.solar,
                            controlAffinity: ListTileControlAffinity.leading,
                            enabled: enabled,
                            onChanged: enabled
                                ? (_) {
                                    onToggleShowTarget();
                                    setPopupState(() => target = !target);
                                  }
                                : null,
                          ),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            title: const Text(
                              '주변 천체 표시',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                            value: nearby,
                            activeColor: AppColors.solar,
                            controlAffinity: ListTileControlAffinity.leading,
                            enabled: enabled,
                            onChanged: enabled
                                ? (_) {
                                    onToggleShowNearby();
                                    setPopupState(() => nearby = !nearby);
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── _InfoCard ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(content, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ── _LocationMapCard ─────────────────────────────────────────────────────────

class _LocationMapCard extends StatefulWidget {
  const _LocationMapCard({
    required this.lat,
    required this.lng,
    this.locationName,
    this.address,
  });

  final double lat;
  final double lng;
  final String? locationName;
  final String? address;

  @override
  State<_LocationMapCard> createState() => _LocationMapCardState();
}

class _LocationMapCardState extends State<_LocationMapCard> {
  var _mapsReady = false;
  bool _keyLoaded = false;
  GoogleMapController? _mapController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_keyLoaded) {
      _keyLoaded = true;
      GoogleMapsKeyReadiness.isReady().then((ready) {
        if (mounted) setState(() => _mapsReady = ready);
      });
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = LatLng(widget.lat, widget.lng);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  '촬영 위치',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          if (widget.locationName != null && widget.locationName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Text(
                widget.locationName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (widget.address != null && widget.address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(
                widget.address!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _CoordChip(label: '위도', value: widget.lat.toStringAsFixed(5)),
                const SizedBox(width: 8),
                _CoordChip(label: '경도', value: widget.lng.toStringAsFixed(5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '지도 확대·축소·이동으로 주변 위치를 확인할 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          if (!_keyLoaded)
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_mapsReady)
            Container(
              height: 80,
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  '지도 구성을 사용할 수 없습니다. 앱 빌드 상태를 확인해 주세요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: GoogleMap(
                  key: ValueKey('gallery_view_map_${widget.lat}_${widget.lng}'),
                  initialCameraPosition: CameraPosition(
                    target: target,
                    zoom: 11,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('photo_location'),
                      position: target,
                    ),
                  },
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  // 부모 스크롤뷰와 제스처 충돌 방지 → 드래그로 지도 이동 가능
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new,
                    ),
                  },
                  zoomControlsEnabled: true,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── _NoLocationCard ──────────────────────────────────────────────────────────

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard({super.key, this.locationName, this.address});

  final String? locationName;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation =
        (locationName != null && locationName!.isNotEmpty) ||
        (address != null && address!.isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                '촬영 위치',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasLocation) ...[
            if (locationName != null && locationName!.isNotEmpty)
              Text(
                locationName!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (address != null && address!.isNotEmpty)
              Text(
                address!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ] else
            Text(
              '미입력',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

// ── _CoordChip ───────────────────────────────────────────────────────────────

class _CoordChip extends StatelessWidget {
  const _CoordChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textSecondary.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

enum _Action { edit, delete }

// ── _MultiFieldCard ───────────────────────────────────────────────────────────

class _MultiFieldCard extends StatelessWidget {
  const _MultiFieldCard({
    super.key,
    required this.icon,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final List<_FieldRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows.map((r) => r.build(context)),
        ],
      ),
    );
  }
}

class _FieldRow {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
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
