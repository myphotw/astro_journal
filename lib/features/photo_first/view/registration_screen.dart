import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/models/plate_solve_result.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/plate_solve_service.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../../shared/widgets/integration_minutes_field.dart';
import '../../../shared/widgets/material_date_time_picker_field.dart';
import '../../catalog/view/metadata_review_screen.dart';
import '../models/registration_session.dart';
import '../widgets/registration_cached_image.dart';
import '../widgets/registration_target_search_panel.dart';

/// 단일 화면 위저드 사진 등록 (다중 사진은 세션 큐).
///
/// 완료 시 [List<RegistrationOutcome>]을 pop한다. 취소 시 null.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.sessions,
    required this.allObjects,
    this.skipTargetStep = false,
  }) : assert(sessions.length > 0);

  factory RegistrationScreen.single({
    Key? key,
    required RegistrationSession session,
    required List<CatalogObject> allObjects,
    bool skipTargetStep = false,
  }) {
    return RegistrationScreen(
      key: key,
      sessions: [session],
      allObjects: allObjects,
      skipTargetStep: skipTargetStep,
    );
  }

  final List<RegistrationSession> sessions;
  final List<CatalogObject> allObjects;
  final bool skipTargetStep;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  static const _animDuration = Duration(milliseconds: 250);
  static const _animCurve = Curves.easeOutCubic;

  List<RegistrationWizardStep> _steps = const [];
  late int _stepIndex;
  var _photoIndex = 0;
  var _goingForward = true;
  final _outcomes = <RegistrationOutcome>[];

  late final TextEditingController _stackCtrl;
  late final TextEditingController _singleExpCtrl;
  late final TextEditingController _totalExpCtrl;
  late final TextEditingController _filterCtrl;
  late final TextEditingController _isoCtrl;
  late final TextEditingController _fstopCtrl;
  late final TextEditingController _focalCtrl;
  late final TextEditingController _locationNameCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _memoCtrl;

  List<Equipment> _equipmentList = const [];
  final ValueNotifier<bool> _isGeocoding = ValueNotifier(false);
  final ValueNotifier<String?> _geocodedLocation = ValueNotifier(null);
  final ValueNotifier<bool> _showMap = ValueNotifier(false);
  final ValueNotifier<bool> _thumbReady = ValueNotifier(false);

  RegistrationSession? _listenedSession;
  VoidCallback? _exifListener;

  RegistrationSession get session => widget.sessions[_photoIndex];
  int get _photoTotal => widget.sessions.length;
  bool get _isLastPhoto => _photoIndex >= _photoTotal - 1;

  @override
  void initState() {
    super.initState();
    _stepIndex = 0;
    _rebuildSteps();

    _stackCtrl = TextEditingController();
    _singleExpCtrl = TextEditingController();
    _totalExpCtrl = TextEditingController();
    _filterCtrl = TextEditingController();
    _isoCtrl = TextEditingController();
    _fstopCtrl = TextEditingController();
    _focalCtrl = TextEditingController();
    _locationNameCtrl = TextEditingController();
    _latCtrl = TextEditingController();
    _lngCtrl = TextEditingController();
    _memoCtrl = TextEditingController();

    _bindSessionControllers(session);
    _attachExifListener(session);
    unawaited(_bootstrapCurrent());
    unawaited(_loadEquipment());
  }

  /// 메타에 대상이 있거나(해석 완료/대기), 카탈로그에서 건너뛴 경우 대상검색을 숨긴다.
  bool get _shouldShowTargetStep {
    if (widget.skipTargetStep) return false;
    if (session.selectedObject != null) return false;
    final metaTarget = session.targetNameOverride?.trim().isNotEmpty == true
        ? session.targetNameOverride!.trim()
        : (session.payload.exifInfo.targetName?.trim() ?? '');
    if (metaTarget.isEmpty) return true;
    // 메타 대상명 있음: 분석 중이면 숨김, 해석 실패 시에만 검색 노출
    return session.isExifReady;
  }

  void _rebuildSteps() {
    final previous = _steps.isEmpty
        ? null
        : _steps[_stepIndex.clamp(0, _steps.length - 1)];
    final hadTargetStep = _steps.contains(RegistrationWizardStep.target);
    _steps = [
      if (_shouldShowTargetStep) RegistrationWizardStep.target,
      RegistrationWizardStep.shooting,
      RegistrationWizardStep.location,
      RegistrationWizardStep.memo,
    ];
    final hasTargetStep = _steps.contains(RegistrationWizardStep.target);
    // 메타 해석 실패로 대상검색이 다시 생기면 해당 단계로 이동
    if (!hadTargetStep && hasTargetStep && session.selectedObject == null) {
      _stepIndex = _steps.indexOf(RegistrationWizardStep.target);
      return;
    }
    if (previous == null) {
      _stepIndex = 0;
      return;
    }
    final kept = _steps.indexOf(previous);
    _stepIndex = kept >= 0 ? kept : 0;
  }

  void _bindSessionControllers(RegistrationSession s) {
    _stackCtrl.text = s.stackNum != null ? '${s.stackNum}' : '';
    _singleExpCtrl.text = s.singleExpSecDigits ?? '';
    _totalExpCtrl.text = s.totalExpMinutesDigits ?? '';
    _filterCtrl.text = s.filter ?? '';
    _isoCtrl.text = s.isoDigits ?? '';
    _fstopCtrl.text = s.fstopDigits ?? '';
    _focalCtrl.text = s.focalDigits ?? '';
    _locationNameCtrl.text = s.locationName ?? '';
    _latCtrl.text = s.lat != null ? s.lat!.toStringAsFixed(6) : '';
    _lngCtrl.text = s.lng != null ? s.lng!.toStringAsFixed(6) : '';
    _memoCtrl.text = s.memo ?? '';
  }

  void _attachExifListener(RegistrationSession s) {
    _detachExifListener();
    _listenedSession = s;
    _exifListener = () {
      if (!mounted) return;
      _bindSessionControllers(s);
      _rebuildSteps();
      setState(() {});
      if (s.isExifReady) unawaited(_fetchLocationName());
    };
    s.exifReady.addListener(_exifListener!);
  }

  void _detachExifListener() {
    final listened = _listenedSession;
    final listener = _exifListener;
    if (listened != null && listener != null) {
      listened.exifReady.removeListener(listener);
    }
    _listenedSession = null;
    _exifListener = null;
  }

  Future<void> _bootstrapCurrent() async {
    _thumbReady.value = false;
    await session.ensureThumbnailLoaded();
    if (!mounted) return;
    _thumbReady.value = true;
    if (session.isExifReady) unawaited(_fetchLocationName());
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _showMap.value = true;
    });
  }

  Future<void> _advanceToPhoto(int index) async {
    _detachExifListener();
    _photoIndex = index;
    _goingForward = true;
    _showMap.value = false;
    _geocodedLocation.value = null;
    _bindSessionControllers(session);
    _rebuildSteps();
    _stepIndex = 0;
    _attachExifListener(session);
    setState(() {});
    await _bootstrapCurrent();
  }

  Future<void> _loadEquipment() async {
    final repo = context.read<EquipmentRepository>();
    final list = await repo.getAll(activeOnly: true);
    if (!mounted) return;
    setState(() => _equipmentList = list);
  }

  Future<void> _fetchLocationName() async {
    final lat = session.lat;
    final lng = session.lng;
    if (lat == null || lng == null) return;

    _isGeocoding.value = true;
    try {
      final geocodingService = context.read<GeocodingService>();
      final result = await geocodingService.getLocationInfo(lat, lng);
      if (!mounted) return;
      if (result != null) {
        final label = result.address.trim().isNotEmpty
            ? result.address.trim()
            : result.locationName.trim();
        if (label.isEmpty) return;
        _geocodedLocation.value = label;
        final current = _locationNameCtrl.text.trim();
        // 비어 있거나 번지 숫자만 있으면 행정주소로 교체
        if (current.isEmpty || RegExp(r'^[\d\-\s]+$').hasMatch(current)) {
          _locationNameCtrl.text = label;
          session.locationName = label;
        }
      }
    } finally {
      if (mounted) _isGeocoding.value = false;
    }
  }

  @override
  void dispose() {
    _detachExifListener();
    _stackCtrl.dispose();
    _singleExpCtrl.dispose();
    _totalExpCtrl.dispose();
    _filterCtrl.dispose();
    _isoCtrl.dispose();
    _fstopCtrl.dispose();
    _focalCtrl.dispose();
    _locationNameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _memoCtrl.dispose();
    _isGeocoding.dispose();
    _geocodedLocation.dispose();
    _showMap.dispose();
    _thumbReady.dispose();
    super.dispose();
  }

  RegistrationWizardStep get _currentStep => _steps[_stepIndex];
  bool get _isLastStep => _stepIndex >= _steps.length - 1;

  String get _appBarTitle => switch (_currentStep) {
    RegistrationWizardStep.target => '대상 선택',
    RegistrationWizardStep.shooting => '촬영 정보',
    RegistrationWizardStep.location => '위치',
    RegistrationWizardStep.memo => '메모 · 확인',
  };

  String get _primaryButtonLabel {
    if (!_isLastStep) return '다음';
    if (!_isLastPhoto) return '다음 사진';
    return '저장';
  }

  /// 모든 단계 입력값을 세션에 반영 (메모 요약·저장용).
  void _syncCurrentStepToSession() {
    session.stackNum = int.tryParse(_stackCtrl.text.trim());
    session.singleExpSecDigits = _singleExpCtrl.text.trim();
    session.totalExpMinutesDigits = _totalExpCtrl.text.trim();
    session.filter = _filterCtrl.text.trim();
    session.isoDigits = _isoCtrl.text.trim();
    session.fstopDigits = _fstopCtrl.text.trim();
    session.focalDigits = _focalCtrl.text.trim();
    session.locationName = _locationNameCtrl.text.trim();
    session.lat = double.tryParse(_latCtrl.text.trim());
    session.lng = double.tryParse(_lngCtrl.text.trim());
    session.memo = _memoCtrl.text.trim();
  }

  bool _canProceed() {
    if (_currentStep == RegistrationWizardStep.target) {
      return session.selectedObject != null;
    }
    return true;
  }

  void _onBack() {
    if (_stepIndex > 0) {
      _syncCurrentStepToSession();
      setState(() {
        _goingForward = false;
        _stepIndex -= 1;
      });
      return;
    }
    if (_photoIndex > 0) {
      _syncCurrentStepToSession();
      unawaited(
        _advanceToPhoto(_photoIndex - 1).then((_) {
          if (!mounted) return;
          setState(() {
            _goingForward = false;
            _stepIndex = _steps.length - 1;
          });
        }),
      );
      return;
    }
    Navigator.of(context).pop<List<RegistrationOutcome>>(null);
  }

  void _onNext() {
    if (!_canProceed()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('촬영 대상을 선택해 주세요.'),
          duration: Duration(milliseconds: 1400),
        ),
      );
      return;
    }
    _syncCurrentStepToSession();
    if (_isLastStep) {
      unawaited(_onSaveOrAdvance());
      return;
    }
    setState(() {
      _goingForward = true;
      _stepIndex += 1;
    });
  }

  Future<void> _onSaveOrAdvance() async {
    if (session.selectedObject == null) return;

    final targetName =
        session.targetNameOverride?.trim() ?? session.selectedObject!.displayId;
    if (targetName.isNotEmpty && _isMismatch(targetName)) {
      final proceed = await _showMismatchDialog(targetName);
      if (!proceed || !mounted) return;
    }

    final confirmed = session.toConfirmedMetadata();
    _outcomes.removeWhere((o) => identical(o.session, session));
    _outcomes.add(RegistrationOutcome(session: session, confirmed: confirmed));

    if (!_isLastPhoto) {
      await _advanceToPhoto(_photoIndex + 1);
      return;
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pop<List<RegistrationOutcome>>(List<RegistrationOutcome>.from(_outcomes));
  }

  bool _isMismatch(String targetName) {
    final object = session.selectedObject;
    if (object == null) return false;
    final n = _norm(targetName);
    return n != _norm(object.displayId) && n != _norm(object.displayCommonName);
  }

  String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  Future<bool> _showMismatchDialog(String autoTarget) async {
    final object = session.selectedObject!;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('대상명 확인'),
        content: Text(
          '선택한 대상: ${object.displayId}\n'
          '입력/인식 대상: $autoTarget\n\n'
          '대상이 서로 다릅니다. 저장하시겠습니까?',
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

  Future<void> _openFullPhoto() async {
    await AppFileImage.precacheForViewer(context, session.localPath);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            FullPhotoViewerPage(photoPath: session.localPath),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: _animCurve),
            child: child,
          );
        },
        transitionDuration: _animDuration,
      ),
    );
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

  Future<void> _runPlateSolve() async {
    final s = session;
    if (s.plateSolveBusy.value) return;
    s.plateSolveBusy.value = true;
    s.plateSolveMessage.value = 'Plate Solve 실행 중…';
    try {
      final service = context.read<PlateSolveService>();
      Equipment? imaging;
      try {
        final list = await context.read<EquipmentRepository>().getAll(
          activeOnly: true,
        );
        final candidates = list.where((e) => e.isImaging && e.hasFov).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        imaging = candidates.isEmpty ? null : candidates.first;
      } catch (_) {}

      final result = await service.solve(
        imagePath: s.localPath,
        imageWidth: s.exifInfo.imageWidth,
        imageHeight: s.exifInfo.imageHeight,
        target: s.selectedObject,
        imagingEquipment: imaging,
      );
      if (!mounted) return;
      s.plateSolveResult = result;
      final modeLabel = result.solveMode == PlateSolveMode.targeted
          ? 'Targeted'
          : (result.solveMode == PlateSolveMode.blind ? 'Blind' : '');
      s.plateSolveMessage.value = result.success
          ? 'Plate Solve 성공${modeLabel.isEmpty ? '' : ' ($modeLabel)'}'
          : (result.errorMessage ?? 'Plate Solve 실패');
      // 등록 요약에 Plate Solve 결과 반영
      setState(() {});
    } catch (e) {
      s.plateSolveMessage.value = 'Plate Solve 오류: $e';
    } finally {
      s.plateSolveBusy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        session.selectedObject?.catalog.accentColor ?? AppColors.solar;
    final progressLabel = _photoTotal > 1
        ? '${_photoIndex + 1} / $_photoTotal'
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          actions: [
            if (progressLabel != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    progressLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            _StepProgressBar(
              current: _stepIndex,
              total: _steps.length,
              labels: [
                for (final s in _steps)
                  switch (s) {
                    RegistrationWizardStep.target => '대상',
                    RegistrationWizardStep.shooting => '촬영',
                    RegistrationWizardStep.location => '위치',
                    RegistrationWizardStep.memo => '메모',
                  },
              ],
            ),
            ValueListenableBuilder<String?>(
              valueListenable: session.analysisMessage,
              builder: (context, msg, _) {
                if (msg == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingLg,
                    AppTheme.spacingSm,
                    AppTheme.spacingLg,
                    0,
                  ),
                  child: Text(
                    msg,
                    style: const TextStyle(
                      color: AppColors.solar,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingLg,
                AppTheme.spacingSm,
                AppTheme.spacingLg,
                AppTheme.spacingSm,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: _thumbReady,
                builder: (context, ready, _) {
                  return RegistrationCachedImage(
                    session: session,
                    onTap: ready ? _openFullPhoto : null,
                  );
                },
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: _animDuration,
                switchInCurve: _animCurve,
                switchOutCurve: _animCurve,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [...previousChildren, ?currentChild],
                  );
                },
                transitionBuilder: (child, animation) {
                  final offsetBegin = Offset(_goingForward ? 0.06 : -0.06, 0);
                  final slide =
                      Tween<Offset>(
                        begin: offsetBegin,
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(parent: animation, curve: _animCurve),
                      );
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey('$_photoIndex-$_stepIndex'),
                  child: _buildStepBody(),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              AppTheme.spacingSm,
              AppTheme.spacingLg,
              AppTheme.spacingLg,
            ),
            child: FilledButton(
              onPressed: _onNext,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                _primaryButtonLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    return switch (_currentStep) {
      RegistrationWizardStep.target => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLg),
        child: RegistrationTargetSearchPanel(
          allObjects: widget.allObjects,
          selected: session.selectedObject,
          onSelected: (obj) {
            setState(() => session.selectTarget(obj));
          },
        ),
      ),
      RegistrationWizardStep.shooting => _ShootingStep(
        session: session,
        equipmentList: _equipmentList,
        stackCtrl: _stackCtrl,
        singleExpCtrl: _singleExpCtrl,
        totalExpCtrl: _totalExpCtrl,
        filterCtrl: _filterCtrl,
        isoCtrl: _isoCtrl,
        fstopCtrl: _fstopCtrl,
        focalCtrl: _focalCtrl,
        onCapturedAtChanged: (v) => setState(() => session.capturedAt = v),
        onEquipmentChanged: (v) => setState(() => session.equipment = v),
      ),
      RegistrationWizardStep.location => _LocationStep(
        locationNameCtrl: _locationNameCtrl,
        latCtrl: _latCtrl,
        lngCtrl: _lngCtrl,
        isGeocoding: _isGeocoding,
        geocodedLocation: _geocodedLocation,
        showMap: _showMap,
        onOpenMaps: _openGoogleMaps,
      ),
      RegistrationWizardStep.memo => _MemoStep(
        session: session,
        memoCtrl: _memoCtrl,
        onPlateSolve: _runPlateSolve,
      ),
    };
  }
}

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({
    required this.current,
    required this.total,
    required this.labels,
  });

  final int current;
  final int total;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLg,
        AppTheme.spacingSm,
        AppTheme.spacingLg,
        0,
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (current + 1) / total,
              minHeight: 3,
              backgroundColor: AppColors.textSecondary.withValues(alpha: 0.2),
              color: AppColors.solar,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == current
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: i <= current
                          ? AppColors.solar
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ShootingStep extends StatelessWidget {
  const _ShootingStep({
    required this.session,
    required this.equipmentList,
    required this.stackCtrl,
    required this.singleExpCtrl,
    required this.totalExpCtrl,
    required this.filterCtrl,
    required this.isoCtrl,
    required this.fstopCtrl,
    required this.focalCtrl,
    required this.onCapturedAtChanged,
    required this.onEquipmentChanged,
  });

  final RegistrationSession session;
  final List<Equipment> equipmentList;
  final TextEditingController stackCtrl;
  final TextEditingController singleExpCtrl;
  final TextEditingController totalExpCtrl;
  final TextEditingController filterCtrl;
  final TextEditingController isoCtrl;
  final TextEditingController fstopCtrl;
  final TextEditingController focalCtrl;
  final ValueChanged<DateTime?> onCapturedAtChanged;
  final ValueChanged<String?> onEquipmentChanged;

  @override
  Widget build(BuildContext context) {
    final names = <String>{
      for (final e in equipmentList) e.name,
      ?session.equipment,
    }.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      children: [
        const Text(
          'EXIF에서 읽은 값을 확인하고 필요하면 수정하세요.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppTheme.spacingMd),
        MaterialDateTimePickerField(
          value: session.capturedAt,
          onChanged: onCapturedAtChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue:
              session.equipment != null && names.contains(session.equipment)
              ? session.equipment
              : null,
          decoration: const InputDecoration(
            labelText: '장비',
            hintText: '등록된 장비를 선택하세요',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('선택 안 함')),
            ...names.map(
              (name) =>
                  DropdownMenuItem<String?>(value: name, child: Text(name)),
            ),
          ],
          onChanged: onEquipmentChanged,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: stackCtrl,
          label: '스택수',
          hint: '13',
          suffix: '장',
          keyboard: TextInputType.number,
        ),
        _Field(
          controller: singleExpCtrl,
          label: '1장 노출시간',
          hint: '20',
          suffix: '초',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        IntegrationMinutesField(controller: totalExpCtrl, hintText: '30'),
        _Field(controller: filterCtrl, label: '필터', hint: 'LP, LRGB, None'),
        _Field(
          controller: isoCtrl,
          label: 'ISO',
          hint: '200',
          keyboard: TextInputType.number,
        ),
        _Field(
          controller: fstopCtrl,
          label: 'F값',
          hint: '5',
          prefix: 'f/',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        _Field(
          controller: focalCtrl,
          label: '초점거리',
          hint: '160',
          suffix: 'mm',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({
    required this.locationNameCtrl,
    required this.latCtrl,
    required this.lngCtrl,
    required this.isGeocoding,
    required this.geocodedLocation,
    required this.showMap,
    required this.onOpenMaps,
  });

  final TextEditingController locationNameCtrl;
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final ValueNotifier<bool> isGeocoding;
  final ValueNotifier<String?> geocodedLocation;
  final ValueNotifier<bool> showMap;
  final VoidCallback onOpenMaps;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
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
    } catch (e) {
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

      final placeName = result.displayLabel;
      widget.locationNameCtrl.text = placeName;
      widget.latCtrl.text = result.latitude.toStringAsFixed(6);
      widget.lngCtrl.text = result.longitude.toStringAsFixed(6);
      widget.geocodedLocation.value = placeName;
      setState(() {
        _isSearching = false;
        _selectedFavoriteId = null;
      });
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
    widget.latCtrl.text = favorite.latitude.toStringAsFixed(6);
    widget.lngCtrl.text = favorite.longitude.toStringAsFixed(6);
    widget.geocodedLocation.value = favorite.name;
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

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      children: [
        if (_favoritesLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_favorites.isNotEmpty) ...[
          InkWell(
            onTap: _toggleFavoritesMenu,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              isFocused: _favoritesMenuOpen,
              decoration: InputDecoration(
                labelText: '등록 장소 / 즐겨찾기',
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
                maxLines: 2,
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check,
                                size: 18,
                                color: AppColors.solar,
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
            '선택하면 위치명·좌표가 자동으로 채워집니다.',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            final q = value.trim();
            if (q.length >= 2) unawaited(_fetchSuggestions(q));
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
        ),
        if (showSuggestions) ...[
          const SizedBox(height: 4),
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: widget.isGeocoding,
          builder: (context, geocoding, _) {
            return _Field(
              controller: widget.locationNameCtrl,
              label: '위치명',
              hint: geocoding ? '위치 조회 중...' : '예: 경기도 광명시 철산동',
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: widget.geocodedLocation,
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
              child: _Field(
                controller: widget.latCtrl,
                label: '위도',
                hint: '37.493301',
                suffix: '°',
                keyboard: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                controller: widget.lngCtrl,
                label: '경도',
                hint: '126.872002',
                suffix: '°',
                keyboard: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ),
          ],
        ),
        RepaintBoundary(
          child: _StableGpsMap(
            latController: widget.latCtrl,
            lngController: widget.lngCtrl,
            showMapListenable: widget.showMap,
            onOpenMaps: widget.onOpenMaps,
          ),
        ),
      ],
    );
  }
}

class _MemoStep extends StatelessWidget {
  const _MemoStep({
    required this.session,
    required this.memoCtrl,
    required this.onPlateSolve,
  });

  final RegistrationSession session;
  final TextEditingController memoCtrl;
  final VoidCallback onPlateSolve;

  static String _dash(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return '-';
    return t;
  }

  static String _formatCapturedAt(DateTime? dt) {
    if (dt == null) return '-';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final object = session.selectedObject;
    final confirmed = session.toConfirmedMetadata();
    final plate = session.plateSolveResult;

    final targetLabel = object != null
        ? (object.displayCommonName.trim().isNotEmpty &&
                  object.displayCommonName != object.displayName)
              ? '${object.displayName} · ${object.displayCommonName}'
              : object.displayName
        : _dash(session.targetNameOverride);

    final locationLabel = () {
      final name = session.locationName?.trim();
      final lat = session.lat;
      final lng = session.lng;
      if (name != null && name.isNotEmpty && lat != null && lng != null) {
        return '$name\n${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }
      if (name != null && name.isNotEmpty) return name;
      if (lat != null && lng != null) {
        return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }
      return '-';
    }();

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      children: [
        if (object != null) ...[
          Text(
            object.displayName,
            style: TextStyle(
              color: object.catalog.accentColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            object.displayCommonName,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
        ],
        _Field(
          controller: memoCtrl,
          label: '메모',
          hint: '촬영 메모를 입력하세요',
          maxLines: 4,
        ),
        const SizedBox(height: AppTheme.spacingSm),
        ValueListenableBuilder<bool>(
          valueListenable: session.plateSolveBusy,
          builder: (context, busy, _) {
            return OutlinedButton.icon(
              onPressed: busy ? null : onPlateSolve,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(busy ? 'Plate Solve 중…' : 'Plate Solve 실행 (선택)'),
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: session.plateSolveMessage,
          builder: (context, msg, _) {
            if (msg == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                msg,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppTheme.spacingMd),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '등록 요약',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '이전 단계에서 입력·확인한 내용입니다.',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              const _SummarySectionTitle('대상'),
              _SummaryRow(label: '대상', value: targetLabel),
              _SummaryRow(
                label: '인식',
                value: session.detectMethod?.label ?? '-',
              ),
              const _SummarySectionTitle('촬영'),
              _SummaryRow(
                label: '촬영일',
                value: _formatCapturedAt(session.capturedAt),
              ),
              _SummaryRow(label: '장비', value: _dash(session.equipment)),
              _SummaryRow(
                label: 'Stack',
                value: session.stackNum?.toString() ?? '-',
              ),
              _SummaryRow(label: '노출', value: _dash(confirmed.singleExpSec)),
              _SummaryRow(label: '적분', value: _dash(confirmed.totalExpSec)),
              _SummaryRow(label: '필터', value: _dash(confirmed.filter)),
              _SummaryRow(label: 'ISO', value: _dash(confirmed.iso)),
              _SummaryRow(label: '조리개', value: _dash(confirmed.fstop)),
              _SummaryRow(label: '초점', value: _dash(confirmed.focal)),
              const _SummarySectionTitle('위치'),
              _SummaryRow(label: '장소', value: locationLabel),
              const _SummarySectionTitle('메모'),
              _SummaryRow(
                label: '메모',
                value: _dash(
                  memoCtrl.text.trim().isNotEmpty
                      ? memoCtrl.text.trim()
                      : session.memo,
                ),
              ),
              if (plate != null) ...[
                const _SummarySectionTitle('Plate Solve'),
                _SummaryRow(
                  label: '결과',
                  value: plate.success ? '성공' : (plate.errorMessage ?? '실패'),
                ),
                if (plate.success) ...[
                  _SummaryRow(
                    label: 'RA',
                    value: plate.centerRa != null
                        ? '${plate.centerRa!.toStringAsFixed(5)}°'
                        : '-',
                  ),
                  _SummaryRow(
                    label: 'Dec',
                    value: plate.centerDec != null
                        ? '${plate.centerDec!.toStringAsFixed(5)}°'
                        : '-',
                  ),
                  _SummaryRow(
                    label: 'FOV',
                    value: (plate.fovWidth != null && plate.fovHeight != null)
                        ? '${plate.fovWidth!.toStringAsFixed(3)}° × ${plate.fovHeight!.toStringAsFixed(3)}°'
                        : '-',
                  ),
                  _SummaryRow(
                    label: '스케일',
                    value: plate.pixelScale != null
                        ? '${plate.pixelScale!.toStringAsFixed(3)} "/px'
                        : '-',
                  ),
                  _SummaryRow(
                    label: '회전',
                    value: plate.rotation != null
                        ? '${plate.rotation!.toStringAsFixed(2)}°'
                        : '-',
                  ),
                  _SummaryRow(label: '솔버', value: _dash(plate.solver)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummarySectionTitle extends StatelessWidget {
  const _SummarySectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.solar,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard,
    this.maxLines = 1,
    this.suffix,
    this.prefix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboard;
  final int maxLines;
  final String? suffix;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          prefixText: prefix,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 위치 단계 지도 — 부모 setState와 분리.
class _StableGpsMap extends StatefulWidget {
  const _StableGpsMap({
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
  State<_StableGpsMap> createState() => _StableGpsMapState();
}

class _StableGpsMapState extends State<_StableGpsMap>
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

  static const _defaultCenter = LatLng(36.5, 127.8);

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
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 12));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.showMapListenable,
      builder: (context, showMap, _) {
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

        final hasPin = _lat != null && _lng != null;
        final position = hasPin ? LatLng(_lat!, _lng!) : _defaultCenter;
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
            Text(
              hasPin
                  ? '지도를 탭하면 Google Maps 앱이 실행됩니다.'
                  : '위에서 주소를 검색하면 지도에 표시됩니다.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: hasPin ? widget.onOpenMaps : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: GoogleMap(
                    key: const ValueKey('registration_gps_map'),
                    initialCameraPosition: CameraPosition(
                      target: position,
                      zoom: hasPin ? 12 : 6.5,
                    ),
                    markers: {if (_marker != null) _marker!},
                    onMapCreated: (c) => _mapController = c,
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
