import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/detect_method.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../photo_first/models/registration_session.dart';
import '../../photo_first/services/registration_image_cache.dart';
import '../../photo_first/viewmodel/photo_first_registration_view_model.dart';
import '../../photo_first/widgets/registration_cached_image.dart';
import '../../photo_first/widgets/registration_target_search_panel.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../../../shared/widgets/integration_minutes_field.dart';
import '../../../shared/widgets/material_date_time_picker_field.dart';

/// Windows 보정 사진 등록 작업 화면. Drop/파일 선택만 View에 두고 등록 계약은 공유한다.
class PcPhotoRegistrationScreen extends StatefulWidget {
  const PcPhotoRegistrationScreen({super.key});

  @override
  State<PcPhotoRegistrationScreen> createState() => _PcPhotoRegistrationScreenState();
}

class _PcPhotoRegistrationScreenState extends State<PcPhotoRegistrationScreen> {
  static const _extensions = <String>{
    '.bmp', '.heic', '.heif', '.jpeg', '.jpg', '.png', '.tif', '.tiff', '.webp',
  };

  final _sessions = <RegistrationSession>[];
  final _stack = TextEditingController();
  final _singleExposure = TextEditingController();
  final _integration = TextEditingController();
  final _filter = TextEditingController();
  final _iso = TextEditingController();
  final _fStop = TextEditingController();
  final _focalLength = TextEditingController();
  final _locationName = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _memo = TextEditingController();

  List<Equipment> _equipment = const [];
  List<ObservationSite> _sites = const [];
  var _selectedIndex = 0;
  var _isImporting = false;
  var _isSaving = false;
  var _homeDropActive = false;
  var _queueDropActive = false;
  var _previewDropActive = false;

  RegistrationSession? get _session => _sessions.isEmpty ? null : _sessions[_selectedIndex];
  Iterable<TextEditingController> get _controllers => [
    _stack, _singleExposure, _integration, _filter, _iso, _fStop, _focalLength,
    _locationName, _latitude, _longitude, _memo,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_syncCurrentSession);
    }
    unawaited(_loadFormOptions());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_syncCurrentSession)
        ..dispose();
    }
    for (final session in _sessions) {
      session.disposeNotifiers();
    }
    super.dispose();
  }

  Future<void> _loadFormOptions() async {
    final results = await Future.wait([
      context.read<EquipmentRepository>().getAll(activeOnly: true),
      context.read<ObservationSiteRepository>().list(),
    ]);
    if (!mounted) return;
    setState(() {
      _equipment = results[0] as List<Equipment>;
      _sites = results[1] as List<ObservationSite>;
    });
  }

  Future<void> _selectFiles() async {
    if (_isImporting || _isSaving) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    await _importPaths(
      result?.files.map((file) => file.path).whereType<String>().toList() ?? const [],
    );
  }

  Future<void> _importPaths(List<String> paths) async {
    if (_isImporting || _isSaving || paths.isEmpty) return;
    _syncCurrentSession();
    final acceptedPaths = <String>[];
    var ignored = 0;
    for (final path in paths.toSet()) {
      final dot = path.lastIndexOf('.');
      if (dot >= 0 && _extensions.contains(path.substring(dot).toLowerCase())) {
        acceptedPaths.add(path);
      } else {
        ignored += 1;
      }
    }
    if (acceptedPaths.isEmpty) {
      _showMessage('등록할 수 있는 이미지 파일을 찾지 못했습니다.');
      return;
    }

    final priorSession = _session;
    setState(() => _isImporting = true);
    try {
      final vm = context.read<PhotoFirstRegistrationViewModel>();
      final payloads = await vm.copyFilePathsOnly(acceptedPaths);
      if (!mounted) return;
      if (payloads.isEmpty) {
        _showMessage(vm.errorMessage ?? '사진을 앱 저장소로 복사하지 못했습니다.');
        return;
      }
      final sessions = <RegistrationSession>[];
      for (final payload in payloads) {
        final duplicate = await vm.checkDuplicateByFilename(payload);
        if (!mounted) return;
        if (duplicate != null &&
            !(await _confirmDuplicate(payload.originalFilename))) {
          continue;
        }
        sessions.add(RegistrationSession(payload: payload));
      }
      if (!mounted || sessions.isEmpty) return;

      setState(() {
        _sessions.addAll(sessions);
        if (priorSession == null) {
          _selectedIndex = _sessions.length - sessions.length;
          _syncControllersFromSession();
        }
      });
      for (final session in sessions) {
        unawaited(session.ensureThumbnailLoaded());
        unawaited(_enrichSession(session));
      }
      _showMessage(
        ignored > 0
            ? '사진 ${sessions.length}장을 추가했습니다. 지원하지 않는 파일 $ignored개는 제외했습니다.'
            : '사진 ${sessions.length}장을 등록 목록에 추가했습니다.',
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<bool> _confirmDuplicate(String filename) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('중복 등록'),
        content: Text('동일한 파일명($filename)의 촬영 기록이 있습니다.\n\n계속 등록하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('계속 등록')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _enrichSession(RegistrationSession session) async {
    final vm = context.read<PhotoFirstRegistrationViewModel>();
    try {
      final enriched = await vm.enrichPayload(session.payload);
      if (!mounted || !_sessions.contains(session)) return;
      if (session.selectedObject == null) {
        final object = vm.resolveTarget(enriched.exifInfo.targetName);
        if (object != null) {
          session.selectTarget(
            object,
            method: enriched.makerNoteMetadata != null || enriched.ownerNameMetadata != null
                ? DetectMethod.exif
                : DetectMethod.filename,
          );
        }
      }
      session.applyEnrichedPayload(enriched);
    } catch (error) {
      if (mounted && _sessions.contains(session)) session.markAnalysisFailed(error);
    }
    if (mounted && _sessions.contains(session) && identical(session, _session)) {
      setState(_syncControllersFromSession);
    }
  }

  void _selectSession(int index) {
    _syncCurrentSession();
    setState(() {
      _selectedIndex = index;
      _syncControllersFromSession();
    });
  }

  void _syncControllersFromSession() {
    final session = _session;
    if (session == null) return;
    _stack.text = session.stackNum?.toString() ?? '';
    _singleExposure.text = session.singleExpSecDigits ?? '';
    _integration.text = session.totalExpMinutesDigits ?? '';
    _filter.text = session.filter ?? '';
    _iso.text = session.isoDigits ?? '';
    _fStop.text = session.fstopDigits ?? '';
    _focalLength.text = session.focalDigits ?? '';
    _locationName.text = session.locationName ?? '';
    _latitude.text = session.lat?.toStringAsFixed(6) ?? '';
    _longitude.text = session.lng?.toStringAsFixed(6) ?? '';
    _memo.text = session.memo ?? '';
  }

  void _syncCurrentSession() {
    final session = _session;
    if (session == null) return;
    session.stackNum = int.tryParse(_stack.text.trim());
    session.singleExpSecDigits = _singleExposure.text.trim();
    session.totalExpMinutesDigits = _integration.text.trim();
    session.filter = _filter.text.trim();
    session.isoDigits = _iso.text.trim();
    session.fstopDigits = _fStop.text.trim();
    session.focalDigits = _focalLength.text.trim();
    session.locationName = _locationName.text.trim();
    session.lat = double.tryParse(_latitude.text.trim());
    session.lng = double.tryParse(_longitude.text.trim());
    session.memo = _memo.text.trim();
  }

  Future<void> _registerAll() async {
    _syncCurrentSession();
    final missing = _sessions.where((session) => session.selectedObject == null).length;
    if (missing > 0) {
      _showMessage('등록할 사진 $missing장의 대상을 선택하세요.');
      return;
    }
    setState(() => _isSaving = true);
    final photoVm = context.read<PhotoFirstRegistrationViewModel>();
    final catalogVm = context.read<CatalogViewModel>();
    final saved = <RegistrationSession>[];
    String? errorMessage;
    try {
      for (final session in _sessions) {
        final record = await photoVm.registerPhoto(
          object: session.selectedObject!,
          payload: session.payload,
          confirmed: session.toConfirmedMetadata(),
          detectMethod: session.detectMethod,
          plateSolve: session.plateSolveResult,
        );
        if (record == null) {
          errorMessage = photoVm.errorMessage ?? '사진을 등록하지 못했습니다.';
          break;
        }
        saved.add(session);
        RegistrationImageCache.evict(session.localPath);
        _applyCatalogCapture(catalogVm, record, session);
      }
      if (!mounted) return;
      await Future.wait([
        context.read<GalleryViewModel>().load(silent: true),
        context.read<StatsViewModel>().load(),
        context.read<HomeViewModel>().load(deferHeavyWork: true),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere(saved.contains);
        for (final session in saved) {
          session.disposeNotifiers();
        }
        _selectedIndex = _sessions.isEmpty ? 0 : _selectedIndex.clamp(0, _sessions.length - 1);
        _syncControllersFromSession();
      });
      _showMessage(errorMessage ?? '사진 ${saved.length}장이 등록되었습니다. 서버 동기화는 백그라운드에서 계속됩니다.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _applyCatalogCapture(CatalogViewModel vm, ShootingRecord record, RegistrationSession session) {
    vm.applyCaptureFromRegistration(
      celestialObjectId: record.celestialObjectId,
      photoUri: record.photoUri ?? session.localPath,
      capturedAt: record.capturedAt,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _sessions.isEmpty ? _buildHome() : _buildWorkspace(),
  );

  Widget _buildHome() => DropTarget(
    onDragEntered: (_) => setState(() => _homeDropActive = true),
    onDragExited: (_) => setState(() => _homeDropActive = false),
    onDragDone: (detail) {
      setState(() => _homeDropActive = false);
      unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
    },
    child: _DropSurface(
      active: _homeDropActive,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_homeDropActive ? Icons.add_photo_alternate : Icons.add_photo_alternate_outlined, size: 56, color: AppColors.messier),
                  const SizedBox(height: AppTheme.spacingMd),
                  Text(_homeDropActive ? '사진을 놓아 등록 목록에 추가' : '보정 완료된 사진을 등록하세요', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppTheme.spacingSm),
                  const Text('여러 장을 선택한 뒤 각 사진의 대상과 촬영 정보를 확인할 수 있습니다.\n메타데이터가 없어도 직접 입력해 등록할 수 있습니다.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: AppTheme.spacingLg),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _selectFiles,
                    icon: _isImporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.folder_open_outlined),
                    label: Text(_isImporting ? '사진 추가 중…' : '사진 선택'),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  const Text('또는 Windows 탐색기에서 사진을 이 영역으로 끌어 놓으세요.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildWorkspace() => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 980) return _buildNarrowWorkspace();
      return Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Row(
          children: [
            SizedBox(width: 244, child: _buildQueue()),
            const SizedBox(width: AppTheme.spacingLg),
            Expanded(child: _buildPreview()),
            const SizedBox(width: AppTheme.spacingLg),
            SizedBox(width: 454, child: _buildInfoPanel()),
          ],
        ),
      );
    },
  );

  Widget _buildNarrowWorkspace() => ListView(
    padding: const EdgeInsets.all(AppTheme.spacingLg),
    children: [
      SizedBox(height: 214, child: _buildQueue(horizontal: true)),
      const SizedBox(height: AppTheme.spacingLg),
      SizedBox(height: 480, child: _buildPreview()),
      const SizedBox(height: AppTheme.spacingLg),
      SizedBox(height: 700, child: _buildInfoPanel()),
    ],
  );

  Widget _buildQueue({bool horizontal = false}) => DropTarget(
    onDragEntered: (_) => setState(() => _queueDropActive = true),
    onDragExited: (_) => setState(() => _queueDropActive = false),
    onDragDone: (detail) {
      setState(() => _queueDropActive = false);
      unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
    },
    child: _DropSurface(
      active: _queueDropActive,
      child: _PhotoQueue(
        sessions: _sessions,
        selectedIndex: _selectedIndex,
        horizontal: horizontal,
        isImporting: _isImporting,
        onAdd: _selectFiles,
        onSelected: _selectSession,
      ),
    ),
  );

  Widget _buildPreview() => DropTarget(
    onDragEntered: (_) => setState(() => _previewDropActive = true),
    onDragExited: (_) => setState(() => _previewDropActive = false),
    onDragDone: (detail) {
      setState(() => _previewDropActive = false);
      unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
    },
    child: _DropSurface(active: _previewDropActive, child: _PcPreview(session: _session!)),
  );

  Widget _buildInfoPanel() {
    final session = _session!;
    final names = <String>{
      for (final item in _equipment) item.name,
      if (session.equipment?.trim().isNotEmpty == true) session.equipment!,
    }.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('등록 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTheme.spacingXs),
            Text(session.isExifReady ? '자동 분석 값을 확인하고 필요하면 수정하세요.' : '메타데이터를 분석하고 있습니다. 빈 항목은 직접 입력할 수 있습니다.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: AppTheme.spacingSm),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Section('대상'),
                    SizedBox(
                      height: 186,
                      child: RegistrationTargetSearchPanel(
                        allObjects: context.read<PhotoFirstRegistrationViewModel>().allObjects,
                        selected: session.selectedObject,
                        onSelected: (object) => setState(() => session.selectTarget(object)),
                      ),
                    ),
                    const _Section('기본 정보'),
                    Row(children: [
                      Expanded(child: MaterialDateTimePickerField(value: session.capturedAt, onChanged: (value) => setState(() => session.capturedAt = value))),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Dropdown<String?>(key: ValueKey('equipment-${session.payload.photoId}-${session.equipment}'), label: '장비', value: names.contains(session.equipment) ? session.equipment : null, items: [const DropdownMenuItem(value: null, child: Text('선택 안 함')), ...names.map((name) => DropdownMenuItem(value: name, child: Text(name)))], onChanged: (value) => setState(() => session.equipment = value))),
                    ]),
                    const _Section('관측 위치'),
                    _Dropdown<String?>(key: ValueKey('site-${session.payload.photoId}'), label: '저장 관측지', hint: '직접 입력 또는 기존 관측지 선택', value: null, items: [const DropdownMenuItem(value: null, child: Text('직접 입력')), ..._sites.map((site) => DropdownMenuItem(value: site.id, child: Text(site.name)))], onChanged: _applySite),
                    _Field(controller: _locationName, label: '관측지 / 위치명', hint: '예: 경기도 광명시 철산동'),
                    Row(children: [
                      Expanded(child: _Field(controller: _latitude, label: '위도', hint: '37.493301', numeric: true)),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Field(controller: _longitude, label: '경도', hint: '126.872002', numeric: true)),
                    ]),
                    const _Section('촬영 정보'),
                    Row(children: [
                      Expanded(child: _Field(controller: _stack, label: '스택수', hint: '13', suffix: '장', numeric: true)),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Field(controller: _singleExposure, label: '1장 노출', hint: '20', suffix: '초', numeric: true)),
                    ]),
                    Row(children: [
                      Expanded(child: IntegrationMinutesField(controller: _integration, label: '총 적산시간', hintText: '30')),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Field(controller: _filter, label: '필터', hint: 'LP, LRGB, None')),
                    ]),
                    Row(children: [
                      Expanded(child: _Field(controller: _iso, label: 'ISO', hint: '200', numeric: true)),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Field(controller: _fStop, label: 'F값', hint: '5', prefix: 'f/', numeric: true)),
                      const SizedBox(width: AppTheme.spacingSm),
                      Expanded(child: _Field(controller: _focalLength, label: '초점거리', hint: '160', suffix: 'mm', numeric: true)),
                    ]),
                    const _Section('메모'),
                    _Field(controller: _memo, label: '보정 / 촬영 메모', hint: '보정 또는 촬영 메모를 입력하세요', maxLines: 3),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            FilledButton.icon(
              onPressed: _isSaving ? null : _registerAll,
              icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
              label: Text(_isSaving ? '로컬에 저장 중…' : '${_sessions.length}장 등록'),
            ),
            const SizedBox(height: AppTheme.spacingXs),
            const Text('등록 후 서버 동기화와 Plate Solve는 백그라운드에서 계속됩니다.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _applySite(String? id) {
    if (id == null) return;
    final site = _sites.where((site) => site.id == id).firstOrNull;
    if (site == null) return;
    setState(() {
      _locationName.text = site.address?.trim().isNotEmpty == true ? site.address! : site.name;
      _latitude.text = site.latitude.toStringAsFixed(6);
      _longitude.text = site.longitude.toStringAsFixed(6);
    });
  }
}

class _DropSurface extends StatelessWidget {
  const _DropSurface({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (active)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.messier.withValues(alpha: 0.13), border: Border.all(color: AppColors.messier, width: 2), borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
            child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_photo_alternate, color: AppColors.messier, size: 38), SizedBox(height: AppTheme.spacingSm), Text('사진을 놓아 등록 목록에 추가', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))])),
          ),
        ),
    ],
  );
}

class _PhotoQueue extends StatelessWidget {
  const _PhotoQueue({required this.sessions, required this.selectedIndex, required this.horizontal, required this.isImporting, required this.onAdd, required this.onSelected});
  final List<RegistrationSession> sessions;
  final int selectedIndex;
  final bool horizontal;
  final bool isImporting;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingSm),
      child: Column(children: [
        Row(children: [const Expanded(child: Text('등록할 사진', style: TextStyle(fontWeight: FontWeight.w700))), Text('${sessions.length}장', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
        TextButton.icon(onPressed: isImporting ? null : onAdd, icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: Text(isImporting ? '사진 추가 중…' : '사진 추가'), style: TextButton.styleFrom(alignment: Alignment.centerLeft)),
        const Divider(height: AppTheme.spacingMd),
        Expanded(child: ListView.separated(
          scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
          itemCount: sessions.length,
          separatorBuilder: (_, _) => SizedBox(width: horizontal ? AppTheme.spacingSm : 0, height: horizontal ? 0 : AppTheme.spacingSm),
          itemBuilder: (context, index) => _QueueItem(session: sessions[index], selected: selectedIndex == index, horizontal: horizontal, onTap: () => onSelected(index)),
        )),
      ]),
    ),
  );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.session, required this.selected, required this.horizontal, required this.onTap});
  final RegistrationSession session;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: horizontal ? 184 : null,
    child: Material(
      color: selected ? AppColors.messier.withValues(alpha: 0.16) : AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingSm),
          child: horizontal
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RegistrationCachedImage(session: session, height: 104), const SizedBox(height: AppTheme.spacingXs), Text(session.payload.originalFilename, maxLines: 1, overflow: TextOverflow.ellipsis), Text(session.selectedObject?.displayName ?? '대상 선택 필요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: session.selectedObject == null ? AppColors.textSecondary : AppColors.messier, fontSize: 11))])
              : Row(children: [SizedBox(width: 64, height: 64, child: RegistrationCachedImage(session: session, height: 64)), const SizedBox(width: AppTheme.spacingSm), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(session.payload.originalFilename, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(session.selectedObject?.displayName ?? '대상 선택 필요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: session.selectedObject == null ? AppColors.textSecondary : AppColors.messier, fontSize: 11))]))]),
        ),
      ),
    ),
  );
}

class _PcPreview extends StatelessWidget {
  const _PcPreview({required this.session});
  final RegistrationSession session;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(session.payload.originalFilename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppTheme.spacingMd),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final longest = math.max(constraints.maxWidth, constraints.maxHeight);
          final cacheWidth = (longest * MediaQuery.devicePixelRatioOf(context)).round().clamp(1200, 1600);
          return Center(child: Image.file(File(session.localPath), cacheWidth: cacheWidth, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true, errorBuilder: (_, _, _) => const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 52), SizedBox(height: AppTheme.spacingSm), Text('이 사진의 미리보기를 표시할 수 없습니다.', style: TextStyle(color: AppColors.textSecondary))])));
        })),
      ]),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(label, style: const TextStyle(color: AppColors.messier, fontWeight: FontWeight.w700, fontSize: 12)));
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: AppTheme.spacingSm), child: DropdownButtonFormField<T>(initialValue: value, decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)), items: items, onChanged: onChanged));
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.hint, this.suffix, this.prefix, this.numeric = false, this.maxLines = 1});
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? suffix;
  final String? prefix;
  final bool numeric;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: AppTheme.spacingSm), child: TextField(controller: controller, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text, maxLines: maxLines, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, prefixText: prefix, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8))));
}
