import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/multi_night_framing_reference.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../data/repositories/multi_night_framing_reference_repository.dart';
import '../../../data/repositories/multi_night_framing_reference_repository_impl.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../../services/multi_night_framing_match_service.dart';
import '../../observation_site/viewmodel/active_observation_site_view_model.dart';

class MultiNightFramingSection extends StatefulWidget {
  const MultiNightFramingSection({
    super.key,
    required this.object,
    this.repository,
    this.equipmentRepository,
    this.observationSiteRepository,
    this.matchService,
    this.optimalWindowStart,
    this.optimalWindowEnd,
    this.optimalWindowSiteId,
    this.darkWindowStart,
    this.darkWindowEnd,
    this.darkWindowSiteId,
  });

  final CatalogObject object;
  final MultiNightFramingReferenceRepository? repository;
  final EquipmentRepository? equipmentRepository;
  final ObservationSiteRepository? observationSiteRepository;
  final MultiNightFramingMatchService? matchService;
  final DateTime? optimalWindowStart;
  final DateTime? optimalWindowEnd;
  final String? optimalWindowSiteId;
  final DateTime? darkWindowStart;
  final DateTime? darkWindowEnd;
  final String? darkWindowSiteId;

  @override
  State<MultiNightFramingSection> createState() =>
      _MultiNightFramingSectionState();
}

class _MultiNightFramingSectionState extends State<MultiNightFramingSection> {
  MultiNightFramingReferenceRepository? _repository;
  Listenable? _repositoryListenable;
  EquipmentRepository? _equipmentRepository;
  ObservationSiteRepository? _siteRepository;
  MultiNightFramingMatchService? _matchService;
  List<MultiNightFramingReference> _references = const [];
  List<Equipment> _equipment = const [];
  List<ObservationSite> _sites = const [];
  bool _loading = true;
  bool _initialized = false;
  String? _message;
  String? _defaultSiteId;
  String? _defaultEquipmentId;
  String? _selectedSiteId;
  String? _selectedEquipmentId;
  MultiNightFramingMatchResult? _result;
  bool _calculating = false;
  int _loadRevision = 0;
  int _calculationRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repository =
        widget.repository ??
        _readOptional<MultiNightFramingReferenceRepositoryImpl>(context);
    _equipmentRepository = widget.equipmentRepository ?? _readOptional(context);
    _siteRepository =
        widget.observationSiteRepository ?? _readOptional(context);
    _matchService = widget.matchService ?? _readOptional(context);
    final activeSite = _readOptional<ActiveObservationSiteViewModel>(context);
    _defaultSiteId = activeSite?.active.selectedSiteId;
    _defaultEquipmentId = activeSite?.active.effectiveEquipmentId;
    final repository = _repository;
    if (repository case final Listenable listenable) {
      _repositoryListenable = listenable;
      listenable.addListener(_onRepositoryChanged);
    }
    _load();
  }

  @override
  void dispose() {
    _repositoryListenable?.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  void _onRepositoryChanged() => _load();

  @override
  void didUpdateWidget(covariant MultiNightFramingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.effectivePrimaryId !=
        widget.object.effectivePrimaryId) {
      _load();
      return;
    }
    if (oldWidget.darkWindowStart != widget.darkWindowStart ||
        oldWidget.darkWindowEnd != widget.darkWindowEnd ||
        oldWidget.darkWindowSiteId != widget.darkWindowSiteId) {
      _recalculate();
    }
  }

  T? _readOptional<T extends Object>(BuildContext context) =>
      context.read<T?>();

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final repository = _repository;
    final equipmentRepository = _equipmentRepository;
    final siteRepository = _siteRepository;
    if (repository == null ||
        equipmentRepository == null ||
        siteRepository == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final values = await Future.wait([
        repository.list(catalogObjectId: widget.object.effectivePrimaryId),
        equipmentRepository.getAll(activeOnly: true),
        siteRepository.list(),
        repository.latestConflictForCatalog(widget.object.effectivePrimaryId),
      ]);
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _references = values[0] as List<MultiNightFramingReference>;
        _equipment = values[1] as List<Equipment>;
        _sites = values[2] as List<ObservationSite>;
        _selectedEquipmentId = _resolveEquipmentId(_selectedEquipmentId);
        _selectedSiteId = _resolveSiteId(_selectedSiteId);
        final conflict = values[3] as String?;
        _message = null;
        if (conflict == 'REFERENCE_ALREADY_EXISTS') {
          _message = '이 대상과 장비에는 이미 기준 구도가 등록되어 있습니다.';
        } else if (conflict?.startsWith('REVISION_CONFLICT') ?? false) {
          _message = '다른 기기에서 기준 구도가 변경되었습니다. 입력 내용은 보존했습니다.';
        }
        _loading = false;
      });
      await _recalculate();
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _message = '기준 구도를 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentReference = _referenceForEquipment(_selectedEquipmentId);
    final equipment = currentReference == null
        ? null
        : _byId(_equipment, currentReference.equipmentId, (value) => value.id);
    final site = currentReference == null
        ? null
        : _byId(_sites, currentReference.siteId, (value) => value.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '같은 구도 이어찍기',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '여러 날에 걸쳐 같은 구도로 촬영할 때 사용할 기준을 등록하고,\n'
              '오늘 같은 구도로 촬영하기 좋은 시간을 확인할 수 있습니다.',
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_repository == null || _matchService == null)
              const Text('같은 구도 기능을 사용할 수 없습니다.')
            else if (currentReference == null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_equipment.isNotEmpty) _buildSelectors(),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    key: const Key('multi-night-register-button'),
                    onPressed: _canRegister
                        ? () => _showEditor(
                            preferredEquipmentId: _selectedEquipmentId,
                            preferredSiteId: _selectedSiteId,
                          )
                        : null,
                    child: const Text('기준 구도 등록'),
                  ),
                ],
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('기준', style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    '${_formatDateTime(currentReference.referenceCapturedAt)} · '
                    '${equipment?.name ?? '장비 정보 없음'} · '
                    '${site?.name ?? '관측지 정보 없음'}',
                  ),
                  OutlinedButton(
                    key: const Key('multi-night-edit-button'),
                    onPressed: () => _showEditor(existing: currentReference),
                    child: const Text('기준 변경'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSelectors(),
              const SizedBox(height: 12),
              if (_calculating) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('오늘 촬영 가능 시간을 확인하고 있습니다.'),
              ] else if (_result != null)
                _InlineMatchResult(
                  result: _result!,
                  matchesOptimalWindow: _matchesOptimalWindow(_result!),
                ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: const TextStyle(color: Colors.orange)),
            ],
          ],
        ),
      ),
    );
  }

  bool get _canRegister => _equipment.isNotEmpty && _sites.isNotEmpty;

  String? _resolveEquipmentId(String? current) {
    if (_equipment.any((value) => value.id == current)) return current;
    if (_equipment.any((value) => value.id == _defaultEquipmentId)) {
      return _defaultEquipmentId;
    }
    if (_references.isNotEmpty &&
        _equipment.any((value) => value.id == _references.first.equipmentId)) {
      return _references.first.equipmentId;
    }
    return _equipment.isEmpty ? null : _equipment.first.id;
  }

  String? _resolveSiteId(String? current) {
    if (_sites.any((value) => value.id == current)) return current;
    if (_sites.any((value) => value.id == _defaultSiteId)) {
      return _defaultSiteId;
    }
    return _sites.isEmpty ? null : _sites.first.id;
  }

  MultiNightFramingReference? _referenceForEquipment(String? equipmentId) {
    if (equipmentId == null) return null;
    return _byId(_references, equipmentId, (value) => value.equipmentId);
  }

  Widget _buildSelectors() => LayoutBuilder(
    builder: (context, constraints) {
      final equipmentSelector = DropdownButtonFormField<String>(
        key: const Key('multi-night-find-equipment'),
        initialValue: _selectedEquipmentId,
        decoration: const InputDecoration(labelText: '장비', isDense: true),
        items: _equipment
            .map(
              (value) =>
                  DropdownMenuItem(value: value.id, child: Text(value.name)),
            )
            .toList(),
        onChanged: (value) {
          if (value == null || value == _selectedEquipmentId) return;
          setState(() {
            _selectedEquipmentId = value;
            _result = null;
            _message = null;
          });
          _recalculate();
        },
      );
      final siteSelector = DropdownButtonFormField<String>(
        key: const Key('multi-night-find-site'),
        initialValue: _selectedSiteId,
        decoration: const InputDecoration(labelText: '오늘 관측지', isDense: true),
        items: _sites
            .map(
              (value) =>
                  DropdownMenuItem(value: value.id, child: Text(value.name)),
            )
            .toList(),
        onChanged: (value) {
          if (value == null || value == _selectedSiteId) return;
          setState(() {
            _selectedSiteId = value;
            _result = null;
            _message = null;
          });
          _recalculate();
        },
      );
      if (constraints.maxWidth < 480) {
        return Column(
          children: [
            equipmentSelector,
            const SizedBox(height: 8),
            siteSelector,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: equipmentSelector),
          const SizedBox(width: 12),
          Expanded(child: siteSelector),
        ],
      );
    },
  );

  Future<void> _recalculate() async {
    final revision = ++_calculationRevision;
    final service = _matchService;
    final reference = _referenceForEquipment(_selectedEquipmentId);
    final equipment = _selectedEquipmentId == null
        ? null
        : _byId(_equipment, _selectedEquipmentId!, (value) => value.id);
    final site = _selectedSiteId == null
        ? null
        : _byId(_sites, _selectedSiteId!, (value) => value.id);
    if (service == null ||
        reference == null ||
        equipment == null ||
        site == null) {
      if (mounted) {
        setState(() {
          _calculating = false;
          _result = null;
          if (reference == null && _selectedEquipmentId != null) {
            _message = '선택한 장비에는 등록된 기준 구도가 없습니다.';
          }
        });
      }
      return;
    }
    if (mounted) setState(() => _calculating = true);
    await Future<void>.delayed(Duration.zero);
    final result = service.findToday(
      object: widget.object,
      reference: reference,
      site: site,
      equipment: equipment,
      darkWindows:
          widget.darkWindowSiteId == site.id &&
              widget.darkWindowStart != null &&
              widget.darkWindowEnd != null
          ? [
              (
                nightStart: widget.darkWindowStart!,
                nightEnd: widget.darkWindowEnd!,
              ),
            ]
          : null,
    );
    if (!mounted || revision != _calculationRevision) return;
    setState(() {
      _result = result;
      _calculating = false;
    });
  }

  bool _matchesOptimalWindow(MultiNightFramingMatchResult result) {
    final optimalStart = widget.optimalWindowStart;
    final optimalEnd = widget.optimalWindowEnd;
    if (optimalStart == null ||
        optimalEnd == null ||
        widget.optimalWindowSiteId != result.site.id) {
      return false;
    }
    final start = result.rangeStart ?? result.recommendedAt;
    final end = result.rangeEnd ?? result.recommendedAt;
    if (start == null || end == null) return false;
    return !end.isBefore(optimalStart) && !start.isAfter(optimalEnd);
  }

  Future<void> _showEditor({
    MultiNightFramingReference? existing,
    String? preferredEquipmentId,
    String? preferredSiteId,
  }) async {
    if (!_canRegister) {
      setState(() => _message = '활성 장비와 관측지를 먼저 등록해주세요.');
      return;
    }
    final input = await showDialog<_ReferenceInput>(
      context: context,
      builder: (context) => _ReferenceEditorDialog(
        object: widget.object,
        equipment: _equipment,
        sites: _sites,
        existing: existing,
        defaultEquipmentId: preferredEquipmentId ?? _defaultEquipmentId,
        defaultSiteId: preferredSiteId ?? _defaultSiteId,
      ),
    );
    if (input == null || !mounted) return;
    final service = _matchService!;
    final repository = _repository!;
    try {
      if (input.delete) {
        if (existing != null) await repository.delete(existing.id);
        await _load();
        if (!mounted) return;
        setState(() => _message = '기준 구도가 삭제되었습니다.');
        return;
      }
      final value = service.buildReference(
        object: widget.object,
        capturedAt: input.capturedAt!,
        site: input.site!,
        equipment: input.equipment!,
        existing: existing,
      );
      if (existing == null) {
        await repository.create(value);
      } else {
        await repository.update(value);
      }
      await _load();
      if (!mounted) return;
      setState(() => _message = '기준 구도가 저장되었습니다.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString().contains('UNIQUE')
            ? '이 대상과 장비에는 이미 기준 구도가 등록되어 있습니다.'
            : '기준 구도를 저장하지 못했습니다.';
      });
    }
  }

  static T? _byId<T>(
    List<T> values,
    String id,
    String Function(T value) getId,
  ) {
    for (final value in values) {
      if (getId(value) == id) return value;
    }
    return null;
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
        '${local.day.toString().padLeft(2, '0')} '
        '${_formatTime(local)}';
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _InlineMatchResult extends StatelessWidget {
  const _InlineMatchResult({
    required this.result,
    required this.matchesOptimalWindow,
  });

  final MultiNightFramingMatchResult result;
  final bool matchesOptimalWindow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        key: const Key('multi-night-inline-result'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.isAvailable) ...[
                const Text(
                  '오늘 같은 구도로 촬영할 수 있습니다.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    _InlineValue(
                      label: '오늘',
                      value: _formatTime(result.recommendedAt!),
                    ),
                    if (result.rangeStart != null && result.rangeEnd != null)
                      _InlineValue(
                        label: '권장',
                        value:
                            '${_formatTime(result.rangeStart!)}~${_formatTime(result.rangeEnd!)}',
                      ),
                    _InlineValue(
                      label: '구도 차이',
                      value: result.framingDifferenceLabel,
                    ),
                  ],
                ),
                if (matchesOptimalWindow) ...[
                  const SizedBox(height: 8),
                  const Text('추천 촬영시간과도 잘 맞습니다.'),
                ],
              ] else ...[
                const Text(
                  '오늘은 같은 구도로 촬영하기 어렵습니다.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  result.unavailableReason ?? '오늘은 이전 촬영과 같은 구도를 재현하기 어렵습니다.',
                ),
                if (result.darkStart != null) ...[
                  const SizedBox(height: 4),
                  Text('${_formatTime(result.darkStart!)} 이후 촬영을 권장합니다.'),
                ],
              ],
              ExpansionTile(
                key: const Key('multi-night-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('상세'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        if (result.framingMatchAt != null)
                          _InlineValue(
                            label: '구도 일치 예상시간',
                            value: _formatTime(result.framingMatchAt!),
                          ),
                        if (result.darkStart != null)
                          _InlineValue(
                            label: '하늘이 충분히 어두워지는 시간',
                            value: _formatTime(result.darkStart!),
                          ),
                        _InlineValue(
                          label: '기준 HA',
                          value:
                              '${result.reference.referenceHourAngleDeg.toStringAsFixed(2)}°',
                        ),
                        _InlineValue(
                          label: '오늘 HA',
                          value: '${result.hourAngleDeg.toStringAsFixed(2)}°',
                        ),
                        _InlineValue(
                          label: '기준 PA',
                          value:
                              '${result.reference.referenceParallacticAngleDeg.toStringAsFixed(2)}°',
                        ),
                        _InlineValue(
                          label: '오늘 PA',
                          value:
                              '${result.parallacticAngleDeg.toStringAsFixed(2)}°',
                        ),
                        _InlineValue(
                          label: 'PA 차이',
                          value:
                              '${result.parallacticAngleDifferenceDeg.toStringAsFixed(2)}°',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _InlineValue extends StatelessWidget {
  const _InlineValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label  ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextSpan(
          text: value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _ReferenceEditorDialog extends StatefulWidget {
  const _ReferenceEditorDialog({
    required this.object,
    required this.equipment,
    required this.sites,
    this.existing,
    this.defaultEquipmentId,
    this.defaultSiteId,
  });

  final CatalogObject object;
  final List<Equipment> equipment;
  final List<ObservationSite> sites;
  final MultiNightFramingReference? existing;
  final String? defaultEquipmentId;
  final String? defaultSiteId;

  @override
  State<_ReferenceEditorDialog> createState() => _ReferenceEditorDialogState();
}

class _ReferenceEditorDialogState extends State<_ReferenceEditorDialog> {
  late DateTime _capturedAt;
  late String _equipmentId;
  late String _siteId;

  @override
  void initState() {
    super.initState();
    _capturedAt =
        widget.existing?.referenceCapturedAt.toLocal() ?? DateTime.now();
    final preferredEquipment =
        widget.existing?.equipmentId ?? widget.defaultEquipmentId;
    _equipmentId =
        widget.equipment.any((value) => value.id == preferredEquipment)
        ? preferredEquipment!
        : widget.equipment.first.id;
    final preferredSite = widget.existing?.siteId ?? widget.defaultSiteId;
    _siteId = widget.sites.any((value) => value.id == preferredSite)
        ? preferredSite!
        : widget.sites.first.id;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '기준 구도 등록' : '기준 변경'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: widget.object.displayName,
            readOnly: true,
            decoration: const InputDecoration(labelText: '대상'),
          ),
          const SizedBox(height: 12),
          const Text('사진 등록 시간이 아닌 실제 촬영을 시작한 시간을 입력하세요.'),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('multi-night-captured-date'),
            contentPadding: EdgeInsets.zero,
            title: const Text('실제 촬영 시작 날짜'),
            subtitle: Text(
              '${_capturedAt.year}.${_capturedAt.month}.${_capturedAt.day}',
            ),
            onTap: _pickDate,
          ),
          ListTile(
            key: const Key('multi-night-captured-time'),
            contentPadding: EdgeInsets.zero,
            title: const Text('실제 촬영 시작 시각'),
            subtitle: Text(
              '${_capturedAt.hour.toString().padLeft(2, '0')}:'
              '${_capturedAt.minute.toString().padLeft(2, '0')}',
            ),
            onTap: _pickTime,
          ),
          DropdownButtonFormField<String>(
            initialValue: _equipmentId,
            decoration: const InputDecoration(labelText: '장비'),
            items: widget.equipment
                .map(
                  (value) => DropdownMenuItem(
                    value: value.id,
                    child: Text(value.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _equipmentId = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _siteId,
            decoration: const InputDecoration(labelText: '관측지'),
            items: widget.sites
                .map(
                  (value) => DropdownMenuItem(
                    value: value.id,
                    child: Text(value.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _siteId = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      if (widget.existing != null)
        TextButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('기준 구도 삭제'),
                content: const Text('등록된 기준 구도를 삭제하시겠습니까?'),
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
            );
            if (confirmed != true || !context.mounted) return;
            Navigator.pop(context, const _ReferenceInput.delete());
          },
          child: const Text('삭제'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('multi-night-save-button'),
        onPressed: _capturedAt.isAfter(DateTime.now())
            ? null
            : () => Navigator.pop(
                context,
                _ReferenceInput(
                  capturedAt: _capturedAt,
                  equipment: widget.equipment.firstWhere(
                    (value) => value.id == _equipmentId,
                  ),
                  site: widget.sites.firstWhere((value) => value.id == _siteId),
                ),
              ),
        child: const Text('저장'),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: _capturedAt.isAfter(DateTime.now())
          ? DateTime.now()
          : _capturedAt,
    );
    if (selected == null) return;
    setState(() {
      _capturedAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _capturedAt.hour,
        _capturedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_capturedAt),
    );
    if (selected == null) return;
    setState(() {
      _capturedAt = DateTime(
        _capturedAt.year,
        _capturedAt.month,
        _capturedAt.day,
        selected.hour,
        selected.minute,
      );
    });
  }
}

class _ReferenceInput {
  const _ReferenceInput({
    required this.capturedAt,
    required this.equipment,
    required this.site,
  }) : delete = false;

  const _ReferenceInput.delete()
    : capturedAt = null,
      equipment = null,
      site = null,
      delete = true;

  final DateTime? capturedAt;
  final Equipment? equipment;
  final ObservationSite? site;
  final bool delete;
}
