import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/detect_method.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/shooting_record.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_registration_service.dart';
import '../../catalog/viewmodel/catalog_view_model.dart';
import '../../catalog/view/metadata_review_screen.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../photo_first/models/registration_session.dart';
import '../../photo_first/services/registration_image_cache.dart';
import '../../photo_first/view/registration_screen.dart';
import '../../photo_first/viewmodel/photo_first_registration_view_model.dart';
import '../../photo_first/widgets/registration_cached_image.dart';
import '../../photo_first/widgets/registration_target_search_panel.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../../../shared/widgets/integration_minutes_field.dart';
import '../../../shared/widgets/material_capture_date_field.dart';

/// Windows 보정 사진 등록 작업 화면. Drop/파일 선택만 View에 두고 등록 계약은 공유한다.
class PcPhotoRegistrationScreen extends StatefulWidget {
  const PcPhotoRegistrationScreen({super.key, this.initialSessions, this.initialObject, this.popWhenFinished = false});

  /// Supplied by catalog entry; every entry saves within this workspace.
  final List<RegistrationSession>? initialSessions;
  final CatalogObject? initialObject;
  final bool popWhenFinished;

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
  var _updatingControllers = false;
  final _autoIntegrationBySession = <RegistrationSession, String>{};
  final _autoFocalBySession = <RegistrationSession, String>{};
  final _externalExifListeners = <RegistrationSession, VoidCallback>{};
  final _savedRecords = <ShootingRecord>[];
  final _saveErrors = <RegistrationSession, String>{};
  final _isGeocoding = ValueNotifier(false);
  final _geocodedLocation = ValueNotifier<String?>(null);
  final _showMap = ValueNotifier(true);

  RegistrationSession? get _session => _sessions.isEmpty ? null : _sessions[_selectedIndex];
  bool get _isWindowsLayout => Theme.of(context).platform == TargetPlatform.windows;
  Iterable<TextEditingController> get _controllers => [
    _stack, _singleExposure, _integration, _focalLength,
    _locationName, _latitude, _longitude, _memo,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialSessions != null) {
      _sessions.addAll(widget.initialSessions!);
      for (final session in _sessions) {
        void onExifReady() {
          if (mounted && identical(_session, session)) setState(_syncControllersFromSession);
        }
        session.exifReady.addListener(onExifReady);
        _externalExifListeners[session] = onExifReady;
      }
    }
    for (final controller in _controllers) {
      controller.addListener(_syncCurrentSession);
    }
    _stack.addListener(_recalculateIntegration);
    _singleExposure.addListener(_recalculateIntegration);
    _integration.addListener(_trackManualIntegrationChange);
    if (_sessions.isNotEmpty) _syncControllersFromSession();
    unawaited(_loadFormOptions());
    if (_sessions.isNotEmpty) unawaited(_fetchLocationName());
  }

  @override
  void dispose() {
    for (final entry in _externalExifListeners.entries) {
      entry.key.exifReady.removeListener(entry.value);
    }
    _stack.removeListener(_recalculateIntegration);
    _singleExposure.removeListener(_recalculateIntegration);
    _integration.removeListener(_trackManualIntegrationChange);
    for (final controller in _controllers) {
      controller
        ..removeListener(_syncCurrentSession)
        ..dispose();
    }
    _isGeocoding.dispose();
    _geocodedLocation.dispose();
    _showMap.dispose();
    if (widget.initialSessions == null) {
      for (final session in _sessions) {
        session.disposeNotifiers();
      }
    }
    super.dispose();
  }

  Future<void> _loadFormOptions() async {
    final photoVm = context.read<PhotoFirstRegistrationViewModel>();
    final results = await Future.wait([
      context.read<EquipmentRepository>().getAll(activeOnly: true),
      context.read<ObservationSiteRepository>().list(),
      if (photoVm.allObjects.isEmpty) photoVm.loadCatalog(),
    ]);
    if (!mounted) return;
    setState(() {
      _equipment = results[0] as List<Equipment>;
      _sites = results[1] as List<ObservationSite>;
    });
  }

  Future<void> _selectFiles() async {
    if (_isImporting || _isSaving) return;
    if (!Platform.isWindows) {
      _syncCurrentSession();
      setState(() => _isImporting = true);
      try {
        final vm = context.read<PhotoFirstRegistrationViewModel>();
        final payloads = await vm.pickPhotosCopyOnly(context);
        if (!mounted) return;
        if (payloads.isEmpty && vm.errorMessage != null) _showMessage(vm.errorMessage!);
        await _addPayloads(payloads);
      } finally {
        if (mounted) setState(() => _isImporting = false);
      }
      return;
    }
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
      await _addPayloads(payloads, priorSession: priorSession, ignored: ignored);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _addPayloads(
    List<PhotoRegistrationPayload> payloads, {
    RegistrationSession? priorSession,
    int ignored = 0,
  }) async {
    if (payloads.isEmpty) return;
    final vm = context.read<PhotoFirstRegistrationViewModel>();
    final sessions = <RegistrationSession>[];
    for (final payload in payloads) {
      final duplicate = await vm.checkDuplicateByFilename(payload);
      if (!mounted) return;
      if (duplicate != null && !(await _confirmDuplicate(payload.originalFilename))) {
        continue;
      }
      final session = RegistrationSession(
        payload: payload,
        selectedObject: widget.initialObject,
        detectMethod: widget.initialObject == null ? null : DetectMethod.manual,
      );
      if (widget.initialObject != null) {
        session.targetNameOverride = widget.initialObject!.displayId;
      }
      sessions.add(session);
    }
    if (!mounted || sessions.isEmpty) return;
    setState(() {
      _sessions.addAll(sessions);
      if (priorSession == null && _sessions.length == sessions.length) {
        _selectedIndex = 0;
        _syncControllersFromSession();
      }
    });
    for (final session in sessions) {
      unawaited(session.ensureThumbnailLoaded());
      unawaited(_enrichSession(session));
    }
    _showMessage(ignored > 0
        ? '사진 ${sessions.length}장을 추가했습니다. 지원하지 않는 파일 $ignored개는 제외했습니다.'
        : '사진 ${sessions.length}장을 등록 목록에 추가했습니다.');
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
      unawaited(_fetchLocationName());
    }
  }

  void _selectSession(int index) {
    _syncCurrentSession();
    setState(() {
      _selectedIndex = index;
      _syncControllersFromSession();
      _geocodedLocation.value = null;
    });
    unawaited(_fetchLocationName());
  }

  void _syncControllersFromSession() {
    final session = _session;
    if (session == null) return;
    _updatingControllers = true;
    try {
      _stack.text = session.stackNum?.toString() ?? '';
      _singleExposure.text = session.singleExpSecDigits ?? '';
      _integration.text = session.totalExpMinutesDigits ?? '';
      _focalLength.text = session.focalDigits ?? '';
      _locationName.text = session.locationName ?? '';
      _latitude.text = session.lat?.toStringAsFixed(6) ?? '';
      _longitude.text = session.lng?.toStringAsFixed(6) ?? '';
      _memo.text = session.memo ?? '';
    } finally {
      _updatingControllers = false;
    }
  }

  void _ensureCaptureDate(RegistrationSession session) {
    if (session.capturedAt != null) return;
    final today = DateTime.now();
    session.capturedAt = DateTime(today.year, today.month, today.day);
  }

  Future<void> _fetchLocationName() async {
    final current = _session;
    final lat = current?.lat;
    final lng = current?.lng;
    if (current == null || lat == null || lng == null) return;
    _isGeocoding.value = true;
    try {
      final result = await context.read<GeocodingService>().getLocationInfo(lat, lng);
      if (!mounted || !identical(current, _session) || result == null) return;
      final label = result.address.trim().isNotEmpty
          ? result.address.trim()
          : result.locationName.trim();
      if (label.isEmpty) return;
      _geocodedLocation.value = label;
      final entered = _locationName.text.trim();
      if (entered.isEmpty || RegExp(r'^[\d\-\s]+$').hasMatch(entered)) {
        _locationName.text = label;
      }
    } finally {
      if (mounted) _isGeocoding.value = false;
    }
  }

  Future<void> _openGoogleMaps() async {
    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openFullPhoto() async {
    final current = _session;
    if (current == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => FullPhotoViewerPage(photoPath: current.localPath)),
    );
  }

  void _syncCurrentSession() {
    if (_updatingControllers) return;
    final session = _session;
    if (session == null) return;
    session.stackNum = int.tryParse(_stack.text.trim());
    session.singleExpSecDigits = _singleExposure.text.trim();
    session.totalExpMinutesDigits = _integration.text.trim();
    session.focalDigits = _focalLength.text.trim();
    session.locationName = _locationName.text.trim();
    session.lat = double.tryParse(_latitude.text.trim());
    session.lng = double.tryParse(_longitude.text.trim());
    session.memo = _memo.text.trim();
  }

  void _recalculateIntegration() {
    if (_updatingControllers) return;
    final current = _session;
    if (current == null) return;
    final calculated = MetadataFormat.integrationMinutesFromStackAndExposure(
      stackCount: _stack.text,
      singleExposureSeconds: _singleExposure.text,
    );
    final previousAuto = _autoIntegrationBySession[current];
    if (calculated == null) {
      if (previousAuto != null && _integration.text == previousAuto) {
        _autoIntegrationBySession.remove(current);
        _integration.clear();
      }
      return;
    }
    if (_integration.text.isNotEmpty && _integration.text != previousAuto) return;
    _autoIntegrationBySession[current] = calculated;
    if (_integration.text != calculated) {
      _integration.text = calculated;
    }
  }

  void _trackManualIntegrationChange() {
    if (_updatingControllers) return;
    final current = _session;
    if (current != null &&
        _integration.text != _autoIntegrationBySession[current]) {
      _autoIntegrationBySession.remove(current);
    }
  }

  Future<void> _registerAll() async {
    if (_isSaving || _sessions.isEmpty) return;
    _syncCurrentSession();
    final missing = _sessions.where((session) => session.selectedObject == null).length;
    if (missing > 0) {
      _showMessage('등록할 사진 $missing장의 대상을 선택하세요.');
      return;
    }
    if (_sessions.any((session) => !session.isExifReady)) {
      _showMessage('사진 분석이 끝나면 등록할 수 있습니다.');
      return;
    }
    for (final session in _sessions) {
      if (!(await _confirmTargetMismatch(session))) return;
      if (!mounted) return;
    }
    for (final session in _sessions) {
      _ensureCaptureDate(session);
    }
    setState(() => _isSaving = true);
    final photoVm = context.read<PhotoFirstRegistrationViewModel>();
    final catalogVm = context.read<CatalogViewModel>();
    final saved = <RegistrationSession>[];
    String? errorMessage;
    try {
      for (final session in List<RegistrationSession>.of(_sessions)) {
        final record = await photoVm.registerPhoto(
          object: session.selectedObject!,
          payload: session.payload,
          confirmed: session.toConfirmedMetadata(),
          detectMethod: session.detectMethod,
          plateSolve: session.plateSolveResult,
        );
        if (record == null) {
          errorMessage = photoVm.errorMessage ?? '사진을 등록하지 못했습니다.';
          _saveErrors[session] = errorMessage;
          continue;
        }
        saved.add(session);
        _savedRecords.add(record);
        _saveErrors.remove(session);
        RegistrationImageCache.evict(session.localPath);
        _applyCatalogCapture(catalogVm, record, session);
      }
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere(saved.contains);
        for (final session in saved) {
          final listener = _externalExifListeners.remove(session);
          if (listener != null) {
            session.exifReady.removeListener(listener);
          }
          _autoIntegrationBySession.remove(session);
          _autoFocalBySession.remove(session);
          session.disposeNotifiers();
        }
        _selectedIndex = _sessions.isEmpty ? 0 : _selectedIndex.clamp(0, _sessions.length - 1);
        _syncControllersFromSession();
      });
      if (saved.isNotEmpty) {
        try {
          await Future.wait([
            context.read<GalleryViewModel>().load(silent: true),
            context.read<StatsViewModel>().load(),
            context.read<HomeViewModel>().load(deferHeavyWork: true),
          ]);
        } catch (_) {
          if (mounted) _showMessage('사진은 저장됐지만 목록 갱신에 실패했습니다. 다시 열어 확인하세요.');
        }
      }
      if (!mounted) return;
      if (_sessions.isEmpty && widget.popWhenFinished) {
        Navigator.of(context).pop(List<ShootingRecord>.of(_savedRecords));
      } else {
        _showMessage(errorMessage == null
            ? '사진 ${saved.length}장이 등록되었습니다. 서버 동기화는 백그라운드에서 계속됩니다.'
            : '사진 ${saved.length}장 저장, ${_saveErrors.length}장 실패. 실패한 사진은 대기열에서 다시 시도할 수 있습니다.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _confirmTargetMismatch(RegistrationSession session) async {
    final object = session.selectedObject!;
    final detected = session.exifInfo.targetName?.trim();
    if (detected == null || detected.isEmpty) return true;
    String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (normalize(detected) == normalize(object.displayId) ||
        normalize(detected) == normalize(object.displayCommonName)) {
      return true;
    }
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('대상명 확인'),
        content: Text('선택한 대상: ${object.displayId}\n인식된 대상: $detected\n\n서로 다릅니다. 저장하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('저장')),
        ],
      ),
    ) ?? false;
  }

  Future<void> _closeRoute() async {
    if (_isSaving) return;
    if (_sessions.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('등록 종료'),
          content: Text('저장하지 않은 사진 ${_sessions.length}장이 있습니다. 등록 화면을 닫으시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('계속 편집')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('닫기')),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop(List<ShootingRecord>.of(_savedRecords));
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
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.popWhenFinished,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.popWhenFinished) {
        unawaited(_closeRoute());
      }
    },
    child: Scaffold(
      appBar: widget.popWhenFinished ? AppBar(title: const Text('사진 등록'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _closeRoute)) : null,
      body: _sessions.isEmpty ? _buildHome() : AbsorbPointer(absorbing: _isSaving, child: _buildWorkspace()),
    ),
  );

  Widget _buildHome() {
    final home = Center(
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
                  if (widget.initialObject != null) ...[
                    const SizedBox(height: AppTheme.spacingSm),
                    Text('선택된 대상: ${widget.initialObject!.displayName}',
                        style: const TextStyle(color: AppColors.messier)),
                    const Text('사진 추가 후 대상 검색에서 변경할 수 있습니다.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                  const SizedBox(height: AppTheme.spacingLg),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _selectFiles,
                    icon: _isImporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.folder_open_outlined),
                    label: Text(_isImporting ? '사진 추가 중…' : '사진 선택'),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  if (_isWindowsLayout)
                    const Text('또는 Windows 탐색기에서 사진을 이 영역으로 끌어 놓으세요.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
    if (!_isWindowsLayout) {
      return SafeArea(child: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        children: [home],
      ));
    }
    return DropTarget(
      onDragEntered: (_) => setState(() => _homeDropActive = true),
      onDragExited: (_) => setState(() => _homeDropActive = false),
      onDragDone: (detail) {
        setState(() => _homeDropActive = false);
        unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
      },
      child: _DropSurface(active: _homeDropActive, child: home),
    );
  }

  Widget _buildWorkspace() => LayoutBuilder(
    builder: (context, constraints) {
      if (!_isWindowsLayout) return _buildMobileWorkspace(constraints.maxWidth);
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
      SizedBox(height: 260, child: _buildQueue(horizontal: true)),
      const SizedBox(height: AppTheme.spacingLg),
      SizedBox(height: 480, child: _buildPreview()),
      const SizedBox(height: AppTheme.spacingLg),
      SizedBox(height: 700, child: _buildInfoPanel()),
    ],
  );

  Widget _buildMobileWorkspace(double width) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.spacingMd, AppTheme.spacingSm,
          AppTheme.spacingMd, AppTheme.spacingXl),
      children: [
        SizedBox(height: 260, child: _buildQueue(horizontal: true)),
        const SizedBox(height: AppTheme.spacingSm),
        SizedBox(height: math.min(width * 0.72, 280), child: _buildPreview()),
        const SizedBox(height: AppTheme.spacingSm),
        _buildInfoPanel(scrollable: false),
      ],
    ),
  );

  Widget _buildQueue({bool horizontal = false}) {
    final queue = _PhotoQueue(
      sessions: _sessions,
      selectedIndex: _selectedIndex,
      horizontal: horizontal,
      isImporting: _isImporting,
      onAdd: _selectFiles,
      onSelected: _selectSession,
      errors: _saveErrors,
    );
    if (!_isWindowsLayout) return queue;
    return DropTarget(
    onDragEntered: (_) => setState(() => _queueDropActive = true),
    onDragExited: (_) => setState(() => _queueDropActive = false),
    onDragDone: (detail) {
      setState(() => _queueDropActive = false);
      unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
    },
    child: _DropSurface(
      active: _queueDropActive,
      child: queue,
    ),
  );
  }

  Widget _buildPreview() {
    final preview = _PcPreview(session: _session!, onTap: _openFullPhoto);
    if (!_isWindowsLayout) return preview;
    return DropTarget(
    onDragEntered: (_) => setState(() => _previewDropActive = true),
    onDragExited: (_) => setState(() => _previewDropActive = false),
    onDragDone: (detail) {
      setState(() => _previewDropActive = false);
      unawaited(_importPaths(detail.files.map((file) => file.path).toList()));
    },
    child: _DropSurface(active: _previewDropActive, child: preview),
  );
  }

  Widget _buildInfoPanel({bool scrollable = true}) {
    final session = _session!;
    final selectedEquipment = _equipment.where((item) => item.id == session.equipmentId).firstOrNull;
    final filters = selectedEquipment?.effectiveCaptureCapability?.filters ?? const [];
    final matchingFilters = filters.where((filter) => filter.name == session.filter).toList();
    final selectedFilterId = matchingFilters.length == 1 ? matchingFilters.single.id : null;
    final compact = MediaQuery.sizeOf(context).width < 600;
    Widget pair(Widget first, Widget second) => compact
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, second])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: first), const SizedBox(width: AppTheme.spacingSm), Expanded(child: second)]);
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Section('대상'),
        RegistrationTargetSearchPanel(
          key: ValueKey(session.payload.photoId),
          embedded: true,
          allObjects: context.read<PhotoFirstRegistrationViewModel>().allObjects,
          selected: session.selectedObject,
          onSelected: (object) => setState(() {
            session.selectTarget(object);
            session.targetNameOverride = object.displayId;
          }),
        ),
        const _Section('기본 정보'),
        pair(
          MaterialCaptureDateField(value: session.capturedAt, onChanged: (value) => setState(() => session.capturedAt = value)),
          _Dropdown<String?>(
            key: ValueKey('equipment-${session.payload.photoId}-${session.equipmentId}'),
            label: '장비',
            value: selectedEquipment?.id,
            items: [
              const DropdownMenuItem(value: null, child: Text('선택 안 함')),
              ..._equipment.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))),
            ],
            onChanged: (id) => _selectEquipment(id),
          ),
        ),
        if (selectedEquipment == null && session.equipment?.isNotEmpty == true)
          Text('기존 장비명: ${session.equipment}', style: const TextStyle(color: AppColors.textSecondary)),
        const _Section('관측 위치'),
        _Dropdown<String?>(key: ValueKey('site-${session.payload.photoId}'), label: '저장 관측지', hint: '직접 입력 또는 기존 관측지 선택', value: null, items: [const DropdownMenuItem(value: null, child: Text('직접 입력')), ..._sites.map((site) => DropdownMenuItem(value: site.id, child: Text(site.name)))], onChanged: _applySite),
        _Field(controller: _locationName, label: '관측지 / 위치명', hint: '예: 경기도 광명시 철산동'),
        pair(
          _Field(controller: _latitude, label: '위도', hint: '37.493301', numeric: true),
          _Field(controller: _longitude, label: '경도', hint: '126.872002', numeric: true),
        ),
        ExpansionTile(
          key: ValueKey('location-tools-${session.payload.photoId}'),
          title: const Text('주소 검색 · 즐겨찾는 관측지 · 지도'),
          children: [RegistrationLocationSection(
            locationNameCtrl: _locationName,
            latCtrl: _latitude,
            lngCtrl: _longitude,
            isGeocoding: _isGeocoding,
            geocodedLocation: _geocodedLocation,
            showMap: _showMap,
            onOpenMaps: _openGoogleMaps,
            showMapPreview: !_isWindowsLayout,
          )],
        ),
        const _Section('촬영 정보'),
        pair(
          _Field(controller: _stack, label: '스택수', hint: '13', suffix: '장', numeric: true),
          _Field(controller: _singleExposure, label: '1장 노출', hint: '20', suffix: '초', numeric: true),
        ),
        pair(
          IntegrationMinutesField(controller: _integration, label: '총 적산시간', hintText: '30'),
          _Dropdown<String?>(
            key: ValueKey('filter-${session.payload.photoId}-${session.equipmentId}'),
            label: '필터',
            value: selectedFilterId,
            hint: selectedEquipment == null ? '먼저 장비를 선택하세요' : '등록된 필터 없음',
            items: [
              const DropdownMenuItem(value: null, child: Text('선택 안 함')),
              ...filters.map((filter) => DropdownMenuItem(value: filter.id, child: Text(filter.name))),
            ],
            onChanged: selectedEquipment == null || filters.isEmpty ? null : (id) => setState(() {
              session.filter = filters.where((filter) => filter.id == id).firstOrNull?.name;
            }),
          ),
        ),
        if (selectedFilterId == null && session.filter?.isNotEmpty == true)
          Text('기존 필터: ${session.filter}', style: const TextStyle(color: AppColors.textSecondary)),
        _Field(controller: _focalLength, label: '초점거리', hint: '160', suffix: 'mm', numeric: true),
        const _Section('메모'),
        _Field(controller: _memo, label: '보정 / 촬영 메모', hint: '보정 또는 촬영 메모를 입력하세요', maxLines: 3),
        ExpansionTile(
          key: ValueKey('summary-${session.payload.photoId}'),
          title: const Text('등록 전 촬영 · 위치 · Plate Solve 요약'),
          children: [AnimatedBuilder(
            animation: Listenable.merge(_controllers.toList()),
            builder: (context, _) => RegistrationSummarySection(session: session, memoCtrl: _memo),
          )],
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('등록 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppTheme.spacingXs),
            Text(session.isExifReady ? '자동 분석 값을 확인하고 필요하면 수정하세요.' : '메타데이터를 분석하고 있습니다. 빈 항목은 직접 입력할 수 있습니다.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (_saveErrors[session] != null)
              Text('저장 실패: ${_saveErrors[session]}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ValueListenableBuilder<String?>(
              valueListenable: session.analysisMessage,
              builder: (context, message, _) => message == null
                  ? const SizedBox.shrink()
                  : Text(message, style: const TextStyle(color: AppColors.solar, fontSize: 12)),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            if (scrollable) Expanded(child: SingleChildScrollView(child: form)) else form,
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

  void _selectEquipment(String? id) {
    final equipment = _equipment.where((item) => item.id == id).firstOrNull;
    setState(() {
      final session = _session!;
      session.equipmentId = equipment?.id;
      session.equipment = equipment?.name;
      final focal = equipment?.focalLengthMm;
      final previousAuto = _autoFocalBySession[session];
      if (focal == null) {
        if (previousAuto != null && _focalLength.text == previousAuto) _focalLength.clear();
        _autoFocalBySession.remove(session);
      } else {
        final value = focal == focal.roundToDouble() ? focal.toInt().toString() : focal.toString();
        _autoFocalBySession[session] = value;
        _focalLength.text = value;
      }
    });
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
  const _PhotoQueue({required this.sessions, required this.selectedIndex, required this.horizontal, required this.isImporting, required this.onAdd, required this.onSelected, required this.errors});
  final List<RegistrationSession> sessions;
  final int selectedIndex;
  final bool horizontal;
  final bool isImporting;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelected;
  final Map<RegistrationSession, String> errors;

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
          itemBuilder: (context, index) => _QueueItem(session: sessions[index], selected: selectedIndex == index, horizontal: horizontal, error: errors[sessions[index]], onTap: () => onSelected(index)),
        )),
      ]),
    ),
  );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.session, required this.selected, required this.horizontal, required this.onTap, this.error});
  final RegistrationSession session;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;
  final String? error;

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
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [RegistrationCachedImage(session: session, height: 72), const SizedBox(height: AppTheme.spacingXs), Text(session.payload.originalFilename, maxLines: 1, overflow: TextOverflow.ellipsis), Text(error ?? session.selectedObject?.displayName ?? '대상 선택 필요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: error != null ? Theme.of(context).colorScheme.error : session.selectedObject == null ? AppColors.textSecondary : AppColors.messier, fontSize: 11))])
              : Row(children: [SizedBox(width: 64, height: 64, child: RegistrationCachedImage(session: session, height: 64)), const SizedBox(width: AppTheme.spacingSm), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(session.payload.originalFilename, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(error ?? session.selectedObject?.displayName ?? '대상 선택 필요', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: error != null ? Theme.of(context).colorScheme.error : session.selectedObject == null ? AppColors.textSecondary : AppColors.messier, fontSize: 11))]))]),
        ),
      ),
    ),
  );
}

class _PcPreview extends StatelessWidget {
  const _PcPreview({required this.session, required this.onTap});
  final RegistrationSession session;
  final VoidCallback onTap;

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
          return GestureDetector(onTap: onTap, child: Center(child: Image.file(File(session.localPath), cacheWidth: cacheWidth, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true, errorBuilder: (_, _, _) => const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.broken_image_outlined, color: AppColors.textSecondary, size: 52), SizedBox(height: AppTheme.spacingSm), Text('이 사진의 미리보기를 표시할 수 없습니다.', style: TextStyle(color: AppColors.textSecondary))]))));
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
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selected = value == null
          ? null
          : items.where((item) => item.value == value).firstOrNull;
      final selectedChild = selected?.child;
      final selectedLabel = selectedChild is Text && selectedChild.data != null
          ? Text(selectedChild.data!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : selectedChild ?? Text(hint ?? '선택 안 함', maxLines: 1, overflow: TextOverflow.ellipsis);
      final enabled = onChanged != null;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
        child: MenuAnchor(
          useRootOverlay: true,
          crossAxisUnconstrained: false,
          style: MenuStyle(
            alignment: AlignmentDirectional.bottomStart,
            fixedSize: WidgetStatePropertyAll(Size.fromWidth(constraints.maxWidth)),
            maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 280)),
            backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
          ),
          menuChildren: [
            for (final item in items)
              MenuItemButton(
                onPressed: enabled && item.enabled
                    ? () => onChanged?.call(item.value)
                    : null,
                trailingIcon: item.value == value ? const Icon(Icons.check, size: 18) : null,
                child: item.child is Text && (item.child as Text).data != null
                    ? Text((item.child as Text).data!, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : item.child,
              ),
          ],
          builder: (context, controller, _) => InkWell(
            onTap: enabled
                ? () => controller.isOpen ? controller.close() : controller.open()
                : null,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              isEmpty: false,
              isFocused: controller.isOpen,
              decoration: InputDecoration(
                labelText: label,
                enabled: enabled,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              child: SizedBox(
                height: 24,
                child: Row(children: [
                  Expanded(child: selectedLabel),
                  const Icon(Icons.arrow_drop_down),
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.label, required this.hint, this.suffix, this.numeric = false, this.maxLines = 1});
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? suffix;
  final bool numeric;
  final int maxLines;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSm),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}
