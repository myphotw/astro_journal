import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/equipment_capture_capability.dart';
import '../../../data/models/equipment_exposure_capability.dart';
import '../../../services/equipment/equipment_capture_presets.dart';

class EquipmentCaptureCapabilityEditor extends StatelessWidget {
  const EquipmentCaptureCapabilityEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final EquipmentCaptureCapability value;
  final ValueChanged<EquipmentCaptureCapability> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('equipment-capture-capability-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          '촬영 지원 사양',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '지원 사양은 추천값이 아니며, 현재 확장 항목은 이 기기에 안전하게 저장됩니다. '
          'NAS API 지원 전에는 다른 기기로 동기화되지 않습니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: EquipmentCapturePreset.values
              .map(
                (preset) => OutlinedButton(
                  key: ValueKey('equipment-preset-${preset.name}'),
                  onPressed: () => _applyPreset(context, preset),
                  child: Text('${preset.label} 프리셋'),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          title: '지원 촬영 모드',
          onAdd: () => _editMode(context),
          addLabel: '모드 추가',
        ),
        if (value.modes.isEmpty)
          const _EmptyHint('등록된 촬영 모드가 없습니다.')
        else
          ...value.modes.map(
            (mode) => _CapabilityTile(
              key: ValueKey('equipment-mode-${mode.id}'),
              title: mode.label,
              subtitle: _exposureLabel(mode.exposureCapability),
              onEdit: () => _editMode(context, mode),
              onDelete: () => onChanged(
                value.copyWith(
                  modes: value.modes
                      .where((item) => item.id != mode.id)
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          title: 'Gain',
          onAdd: () => _editGain(context),
          addLabel: value.gainCapability == null ? '설정' : '수정',
        ),
        if (value.gainCapability == null)
          const _EmptyHint('Gain 사용자 설정이 없는 장비입니다.')
        else
          _CapabilityTile(
            key: const ValueKey('equipment-gain-capability'),
            title: '지원 Gain',
            subtitle: _gainLabel(value.gainCapability!),
            onEdit: () => _editGain(context),
            onDelete: () =>
                onChanged(value.copyWith(clearGainCapability: true)),
          ),
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          title: '지원 필터',
          onAdd: () => _addCustomFilter(context),
          addLabel: '사용자 필터',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in _standardFilters)
              FilterChip(
                key: ValueKey('equipment-filter-${option.id}'),
                label: Text(option.name),
                selected: value.filters.any((item) => item.id == option.id),
                onSelected: (selected) => _toggleFilter(option, selected),
              ),
            for (final option in value.filters.where(
              (item) =>
                  !_standardFilters.any((standard) => standard.id == item.id),
            ))
              InputChip(
                key: ValueKey('equipment-filter-${option.id}'),
                label: Text(option.name),
                onDeleted: () => _removeFilter(option.id),
              ),
          ],
        ),
        if (value.filters.isEmpty) const _EmptyHint('지원 필터가 등록되지 않았습니다.'),
        const SizedBox(height: 18),
        _sectionHeader(
          context,
          title: '채널 조합',
          onAdd: () => _editChannelCombination(context),
          addLabel: '조합 추가',
        ),
        if (value.channelCombinations.isEmpty)
          const _EmptyHint('SHO 등 채널 조합 기능이 없습니다.')
        else
          ...value.channelCombinations.map(
            (combination) => _CapabilityTile(
              key: ValueKey('equipment-channel-${combination.id}'),
              title: combination.name,
              subtitle: combination.ratioAdjustable
                  ? '${combination.primaryLabel}:${combination.secondaryLabel} '
                        '${combination.minPrimaryPercent}~${combination.maxPrimaryPercent}% '
                        '(${combination.stepPercent}% 단위, 합계 100)'
                  : '고정 채널 조합',
              onEdit: () => _editChannelCombination(context, combination),
              onDelete: () => onChanged(
                value.copyWith(
                  channelCombinations: value.channelCombinations
                      .where((item) => item.id != combination.id)
                      .toList(growable: false),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required VoidCallback onAdd,
    required String addLabel,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 18),
        label: Text(addLabel),
      ),
    ],
  );

  Future<void> _applyPreset(
    BuildContext context,
    EquipmentCapturePreset preset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${preset.label} 프리셋 적용'),
        content: const Text(
          '현재 촬영 지원 사양을 프리셋으로 교체합니다. 모드별 실제 제한은 '
          '장비 펌웨어와 사용 환경에 따라 다를 수 있으므로 저장 전에 확인·수정하세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    if (confirmed == true) onChanged(EquipmentCapturePresets.build(preset));
  }

  Future<void> _editMode(
    BuildContext context, [
    EquipmentCaptureModeCapability? existing,
  ]) async {
    var modeType = existing?.type ?? EquipmentCaptureModeType.altAz;
    final labelController = TextEditingController(
      text: existing?.label ?? modeType.label,
    );
    var exposureType = _exposureEditorType(existing?.exposureCapability);
    final valuesController = TextEditingController(
      text: switch (existing?.exposureCapability) {
        DiscreteExposureCapability(:final valuesSeconds) =>
          valuesSeconds.map(_formatNumber).join(', '),
        _ => '',
      },
    );
    final minController = TextEditingController(
      text: switch (existing?.exposureCapability) {
        RangeExposureCapability(:final minSeconds) => _formatNumber(minSeconds),
        FreeInputExposureCapability(:final minSeconds) => _formatNumber(
          minSeconds,
        ),
        _ => '',
      },
    );
    final maxController = TextEditingController(
      text: switch (existing?.exposureCapability) {
        RangeExposureCapability(:final maxSeconds) => _formatNumber(maxSeconds),
        FreeInputExposureCapability(:final maxSeconds) => _formatNumber(
          maxSeconds,
        ),
        _ => '',
      },
    );
    final stepController = TextEditingController(
      text: switch (existing?.exposureCapability) {
        RangeExposureCapability(:final stepSeconds) => _formatNumber(
          stepSeconds,
        ),
        _ => '',
      },
    );

    final result = await showDialog<EquipmentCaptureModeCapability>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '촬영 모드 추가' : '촬영 모드 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<EquipmentCaptureModeType>(
                  initialValue: modeType,
                  decoration: const InputDecoration(labelText: '모드'),
                  items: EquipmentCaptureModeType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (type) {
                    if (type == null) return;
                    setDialogState(() {
                      modeType = type;
                      if (type != EquipmentCaptureModeType.custom) {
                        labelController.text = type.label;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelController,
                  enabled: modeType == EquipmentCaptureModeType.custom,
                  decoration: const InputDecoration(labelText: '표시 이름'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_ExposureEditorType>(
                  initialValue: exposureType,
                  decoration: const InputDecoration(labelText: '노출시간 방식'),
                  items: _ExposureEditorType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (type) => setDialogState(
                    () => exposureType = type ?? _ExposureEditorType.none,
                  ),
                ),
                if (exposureType == _ExposureEditorType.discrete) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: valuesController,
                    decoration: const InputDecoration(
                      labelText: '노출시간 목록 (초)',
                      hintText: '2, 5, 10, 30',
                    ),
                  ),
                ],
                if (exposureType == _ExposureEditorType.range ||
                    exposureType == _ExposureEditorType.freeInput) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: minController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '최소 초'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: maxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '최대 초'),
                  ),
                ],
                if (exposureType == _ExposureEditorType.range) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: stepController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '간격 초'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final mode = EquipmentCaptureModeCapability(
                    id: existing != null && existing.type == modeType
                        ? existing.id
                        : _modeId(modeType),
                    type: modeType,
                    label: labelController.text.trim(),
                    exposureCapability: _buildExposure(
                      exposureType,
                      values: valuesController.text,
                      min: minController.text,
                      max: maxController.text,
                      step: stepController.text,
                    ),
                  );
                  final candidateModes = [
                    for (final item in value.modes)
                      if (item.id != existing?.id) item,
                    mode,
                  ];
                  value.copyWith(modes: candidateModes).validate();
                  Navigator.pop(dialogContext, mode);
                } catch (error) {
                  _showDialogError(dialogContext, error);
                }
              },
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
    labelController.dispose();
    valuesController.dispose();
    minController.dispose();
    maxController.dispose();
    stepController.dispose();
    if (result == null) return;
    onChanged(
      value.copyWith(
        modes: [
          for (final item in value.modes)
            if (item.id != existing?.id && item.id != result.id) item,
          result,
        ],
      ),
    );
  }

  Future<void> _editGain(BuildContext context) async {
    var type = value.gainCapability is RangeGainCapability
        ? GainCapabilityType.range
        : GainCapabilityType.discrete;
    final valuesController = TextEditingController(
      text: switch (value.gainCapability) {
        DiscreteGainCapability(:final values) =>
          values.map(_formatNumber).join(', '),
        _ => '',
      },
    );
    final minController = TextEditingController(
      text: switch (value.gainCapability) {
        RangeGainCapability(:final min) => _formatNumber(min),
        _ => '',
      },
    );
    final maxController = TextEditingController(
      text: switch (value.gainCapability) {
        RangeGainCapability(:final max) => _formatNumber(max),
        _ => '',
      },
    );
    final stepController = TextEditingController(
      text: switch (value.gainCapability) {
        RangeGainCapability(:final step) => _formatNumber(step),
        _ => '',
      },
    );
    final result = await showDialog<EquipmentGainCapability>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gain 지원 범위'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<GainCapabilityType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '입력 방식'),
                  items: const [
                    DropdownMenuItem(
                      value: GainCapabilityType.discrete,
                      child: Text('선택값 목록'),
                    ),
                    DropdownMenuItem(
                      value: GainCapabilityType.range,
                      child: Text('최소·최대·간격'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => type = value ?? GainCapabilityType.discrete,
                  ),
                ),
                if (type == GainCapabilityType.discrete) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: valuesController,
                    decoration: const InputDecoration(
                      labelText: 'Gain 목록',
                      hintText: '0, 10, 20, 30',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: minController,
                    decoration: const InputDecoration(labelText: '최소 Gain'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: maxController,
                    decoration: const InputDecoration(labelText: '최대 Gain'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stepController,
                    decoration: const InputDecoration(labelText: '간격'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final gain = type == GainCapabilityType.discrete
                      ? DiscreteGainCapability(
                          values: _parseNumberList(valuesController.text),
                        )
                      : RangeGainCapability(
                          min: _requiredNumber(minController.text),
                          max: _requiredNumber(maxController.text),
                          step: _requiredNumber(stepController.text),
                        );
                  value.copyWith(gainCapability: gain).validate();
                  Navigator.pop(dialogContext, gain);
                } catch (error) {
                  _showDialogError(dialogContext, error);
                }
              },
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
    valuesController.dispose();
    minController.dispose();
    maxController.dispose();
    stepController.dispose();
    if (result != null) onChanged(value.copyWith(gainCapability: result));
  }

  Future<void> _addCustomFilter(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사용자 정의 필터'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '필터 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final option = EquipmentFilterCapability(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      type: EquipmentFilterType.custom,
      name: name,
    );
    onChanged(value.copyWith(filters: [...value.filters, option]));
  }

  Future<void> _editChannelCombination(
    BuildContext context, [
    EquipmentChannelCombinationCapability? existing,
  ]) async {
    final nameController = TextEditingController(text: existing?.name ?? 'SHO');
    final primaryController = TextEditingController(
      text: existing?.primaryLabel ?? 'SO',
    );
    final secondaryController = TextEditingController(
      text: existing?.secondaryLabel ?? 'HO',
    );
    final minController = TextEditingController(
      text: '${existing?.minPrimaryPercent ?? 0}',
    );
    final maxController = TextEditingController(
      text: '${existing?.maxPrimaryPercent ?? 100}',
    );
    final stepController = TextEditingController(
      text: '${existing?.stepPercent ?? 1}',
    );
    var adjustable = existing?.ratioAdjustable ?? true;
    final result = await showDialog<EquipmentChannelCombinationCapability>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '채널 조합 추가' : '채널 조합 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '조합 이름'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: primaryController,
                  decoration: const InputDecoration(labelText: '첫 채널'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: secondaryController,
                  decoration: const InputDecoration(labelText: '둘째 채널'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('비율 조절 가능'),
                  value: adjustable,
                  onChanged: (value) =>
                      setDialogState(() => adjustable = value),
                ),
                if (adjustable) ...[
                  TextField(
                    controller: minController,
                    decoration: const InputDecoration(labelText: '첫 채널 최소 %'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: maxController,
                    decoration: const InputDecoration(labelText: '첫 채널 최대 %'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stepController,
                    decoration: const InputDecoration(labelText: '조절 단위 %'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '둘째 채널 비율은 100에서 첫 채널 비율을 뺀 값입니다.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final combination = EquipmentChannelCombinationCapability(
                    id:
                        existing?.id ??
                        'channel_${DateTime.now().microsecondsSinceEpoch}',
                    name: nameController.text.trim(),
                    primaryLabel: primaryController.text.trim(),
                    secondaryLabel: secondaryController.text.trim(),
                    ratioAdjustable: adjustable,
                    minPrimaryPercent: adjustable
                        ? _requiredInt(minController.text)
                        : 0,
                    maxPrimaryPercent: adjustable
                        ? _requiredInt(maxController.text)
                        : 100,
                    stepPercent: adjustable
                        ? _requiredInt(stepController.text)
                        : 1,
                  );
                  final combinations = [
                    for (final item in value.channelCombinations)
                      if (item.id != existing?.id) item,
                    combination,
                  ];
                  value.copyWith(channelCombinations: combinations).validate();
                  Navigator.pop(dialogContext, combination);
                } catch (error) {
                  _showDialogError(dialogContext, error);
                }
              },
              child: const Text('적용'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    primaryController.dispose();
    secondaryController.dispose();
    minController.dispose();
    maxController.dispose();
    stepController.dispose();
    if (result == null) return;
    onChanged(
      value.copyWith(
        channelCombinations: [
          for (final item in value.channelCombinations)
            if (item.id != existing?.id) item,
          result,
        ],
      ),
    );
  }

  void _toggleFilter(EquipmentFilterCapability option, bool selected) {
    final filters = value.filters
        .where((item) => item.id != option.id)
        .toList(growable: true);
    if (selected) filters.add(option);
    onChanged(value.copyWith(filters: filters));
  }

  void _removeFilter(String id) {
    onChanged(
      value.copyWith(
        filters: value.filters
            .where((item) => item.id != id)
            .toList(growable: false),
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 6),
    child: ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '수정',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '삭제',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  );
}

enum _ExposureEditorType {
  none('노출시간 미등록'),
  discrete('선택값 목록'),
  range('최소·최대·간격'),
  freeInput('범위 내 자유 입력');

  const _ExposureEditorType(this.label);
  final String label;
}

_ExposureEditorType _exposureEditorType(
  EquipmentExposureCapability? capability,
) => switch (capability) {
  DiscreteExposureCapability() => _ExposureEditorType.discrete,
  RangeExposureCapability() => _ExposureEditorType.range,
  FreeInputExposureCapability() => _ExposureEditorType.freeInput,
  null => _ExposureEditorType.none,
};

EquipmentExposureCapability? _buildExposure(
  _ExposureEditorType type, {
  required String values,
  required String min,
  required String max,
  required String step,
}) => switch (type) {
  _ExposureEditorType.none => null,
  _ExposureEditorType.discrete => DiscreteExposureCapability(
    valuesSeconds: _parseNumberList(values),
  ),
  _ExposureEditorType.range => RangeExposureCapability(
    minSeconds: _requiredNumber(min),
    maxSeconds: _requiredNumber(max),
    stepSeconds: _requiredNumber(step),
  ),
  _ExposureEditorType.freeInput => FreeInputExposureCapability(
    minSeconds: _requiredNumber(min),
    maxSeconds: _requiredNumber(max),
  ),
};

String _modeId(EquipmentCaptureModeType type) => switch (type) {
  EquipmentCaptureModeType.altAz => EquipmentCaptureModeCapability.altAzId,
  EquipmentCaptureModeType.equatorial =>
    EquipmentCaptureModeCapability.equatorialId,
  EquipmentCaptureModeType.altAzDerotated =>
    EquipmentCaptureModeCapability.altAzDerotatedId,
  EquipmentCaptureModeType.custom =>
    'custom_${DateTime.now().microsecondsSinceEpoch}',
};

String _exposureLabel(EquipmentExposureCapability? capability) =>
    switch (capability) {
      DiscreteExposureCapability(:final valuesSeconds) =>
        '${valuesSeconds.map(_formatNumber).join(', ')}초',
      RangeExposureCapability(
        :final minSeconds,
        :final maxSeconds,
        :final stepSeconds,
      ) =>
        '${_formatNumber(minSeconds)}~${_formatNumber(maxSeconds)}초 '
            '(${_formatNumber(stepSeconds)}초 간격)',
      FreeInputExposureCapability(:final minSeconds, :final maxSeconds) =>
        '${_formatNumber(minSeconds)}~${_formatNumber(maxSeconds)}초 자유 입력',
      null => '노출시간 미등록',
    };

String _gainLabel(EquipmentGainCapability capability) => switch (capability) {
  DiscreteGainCapability(:final values) => values.map(_formatNumber).join(', '),
  RangeGainCapability(:final min, :final max, :final step) =>
    '${_formatNumber(min)}~${_formatNumber(max)} (${_formatNumber(step)} 간격)',
};

List<double> _parseNumberList(String text) {
  final values =
      text
          .split(RegExp(r'[,\s]+'))
          .where((item) => item.trim().isNotEmpty)
          .map(double.parse)
          .toSet()
          .toList()
        ..sort();
  if (values.isEmpty) throw const FormatException('값을 하나 이상 입력하세요.');
  return values;
}

double _requiredNumber(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite) {
    throw const FormatException('숫자 값을 확인하세요.');
  }
  return value;
}

int _requiredInt(String text) {
  final value = int.tryParse(text.trim());
  if (value == null) throw const FormatException('정수 값을 확인하세요.');
  return value;
}

String _formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

void _showDialogError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst('Invalid argument(s): ', '');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

const _standardFilters = <EquipmentFilterCapability>[
  EquipmentFilterCapability(
    id: 'filter_off',
    type: EquipmentFilterType.off,
    name: '필터 끄기',
  ),
  EquipmentFilterCapability(
    id: 'broadband',
    type: EquipmentFilterType.broadband,
    name: '광대역',
  ),
  EquipmentFilterCapability(
    id: 'dual_band',
    type: EquipmentFilterType.dualBand,
    name: '듀얼밴드',
  ),
  EquipmentFilterCapability(
    id: 'narrow_band',
    type: EquipmentFilterType.narrowBand,
    name: '협대역',
  ),
];
