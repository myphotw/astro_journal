import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/equipment_recommendation.dart';
import '../../data/models/fov_box.dart';

/// 천체 상세·추천 상세 공용 장비 추천 섹션.
class EquipmentRecommendationSection extends StatelessWidget {
  const EquipmentRecommendationSection({
    super.key,
    required this.recommendation,
    this.isToday = false,
    this.onManageTap,
  });

  final ObjectEquipmentRecommendation recommendation;
  final bool isToday;
  final VoidCallback? onManageTap;

  @override
  Widget build(BuildContext context) {
    if (!recommendation.hasRegisteredEquipment &&
        !recommendation.showImaging &&
        !recommendation.showVisual) {
      return _EmptyCard(onManageTap: onManageTap);
    }

    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isToday ? '오늘 추천 장비' : '추천 장비',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (recommendation.showImaging) ...[
              _SectionHeader(icon: '📷', label: isToday ? '오늘 추천' : '촬영'),
              const SizedBox(height: 6),
              if (recommendation.imaging.isNotEmpty)
                ...recommendation.imaging.map(
                  (item) => _buildImagingRow(context, item),
                )
              else
                Text(
                  _availabilityMessage(
                    recommendation.imagingAvailability,
                    visual: false,
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
            ],
            if (recommendation.showImaging && recommendation.showVisual)
              const SizedBox(height: 12),
            if (recommendation.showVisual) ...[
              const _SectionHeader(icon: '👁', label: '안시'),
              const SizedBox(height: 6),
              if (recommendation.visual.isNotEmpty)
                _buildVisualSection(recommendation.visual)
              else
                Text(
                  _availabilityMessage(
                    recommendation.visualAvailability,
                    visual: true,
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _availabilityMessage(
    EquipmentRecommendationAvailability availability, {
    required bool visual,
  }) {
    return switch (availability) {
      EquipmentRecommendationAvailability.notRegistered =>
        visual ? '등록된 안시 장비가 없습니다.' : '등록된 촬영 장비가 없습니다.',
      EquipmentRecommendationAvailability.insufficientData =>
        visual ? '등록된 안시 장비의 광학 정보가 부족합니다.' : '등록된 촬영 장비의 촬영 정보가 부족합니다.',
      EquipmentRecommendationAvailability.noSuitableMatch ||
      EquipmentRecommendationAvailability.available =>
        visual ? '이 대상에 적합한 안시 장비를 찾지 못했습니다.' : '이 대상에 적합한 촬영 장비를 찾지 못했습니다.',
    };
  }

  Widget _buildImagingRow(
    BuildContext context,
    ImagingEquipmentRecommendation item,
  ) {
    final medal = switch (item.rank) {
      1 => '🥇 ',
      2 => '🥈 ',
      3 => '🥉 ',
      _ => '',
    };
    final description = item.screenFillNote;
    final statusColor =
        item.framingRecommendation == FramingRecommendation.good ||
            item.framingRecommendation == FramingRecommendation.optimal
        ? Colors.lightGreenAccent
        : Colors.orangeAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        key: ValueKey('equipment-imaging-summary-${item.equipment.id}'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: AppColors.textSecondary.withValues(alpha: 0.18),
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 110),
                  child: Text(
                    '$medal${item.equipment.name}',
                    key: ValueKey(
                      'equipment-imaging-name-${item.equipment.id}',
                    ),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              key: ValueKey('equipment-imaging-details-${item.equipment.id}'),
              spacing: 18,
              runSpacing: 5,
              children: [
                _ImagingMetric(
                  key: ValueKey('equipment-imaging-fill-${item.equipment.id}'),
                  label: '화면 점유율',
                  value: '${item.screenFillPercent}%',
                  valueColor: AppColors.messier,
                ),
                _ImagingMetric(
                  key: ValueKey(
                    'equipment-imaging-framing-${item.equipment.id}',
                  ),
                  label: '프레이밍',
                  value: item.framingRecommendation.labelKo,
                  valueColor: AppColors.messier,
                ),
                _ImagingMetric(
                  key: ValueKey(
                    'equipment-imaging-status-${item.equipment.id}',
                  ),
                  label: '촬영 상태',
                  value: item.reason,
                  valueColor: statusColor,
                ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0x26FFFFFF)),
            const SizedBox(height: 8),
            const Text(
              '촬영 설정',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            if (item.captureSettings.isEmpty)
              Text(
                '장비 등록 화면에서 촬영 설정을 추가하면 모드별 지원 범위를 확인할 수 있습니다.',
                key: ValueKey(
                  'equipment-capture-settings-empty-${item.equipment.id}',
                ),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              )
            else
              _CaptureSettingsGrid(
                equipmentId: item.equipment.id,
                items: item.captureSettings,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualSection(List<VisualEquipmentRecommendation> items) {
    final displayItems = isToday
        ? items.where((item) => item.isFeasibleToday).toList()
        : items;

    if (isToday && displayItems.isEmpty) {
      final reason = items.isNotEmpty
          ? items.first.reason
          : '오늘은 안시 관측이 어렵습니다.';
      return Text(
        '안시 비추천 · $reason',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    if (displayItems.length == 1 &&
        !displayItems.first.isRecommended &&
        displayItems.first.eyepiece == null) {
      return Text(
        '비추천 · ${displayItems.first.reason}',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      );
    }

    final byEquipment = <String, List<VisualEquipmentRecommendation>>{};
    for (final item in displayItems) {
      byEquipment.putIfAbsent(item.equipment.id, () => []).add(item);
    }

    final blocks = <Widget>[];
    for (final entry in byEquipment.entries) {
      final combos = entry.value.where((item) => item.eyepiece != null).toList()
        ..sort(
          (a, b) =>
              b.eyepiece!.focalLengthMm.compareTo(a.eyepiece!.focalLengthMm),
        );

      if (combos.isEmpty) {
        final fallback = entry.value.first;
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fallback.equipment.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (fallback.recommendedEyepieceFocalLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '권장 아이피스 ${fallback.recommendedEyepieceFocalLabel}',
                    key: ValueKey(
                      'equipment-visual-ideal-eyepiece-${fallback.equipment.id}',
                    ),
                    style: const TextStyle(
                      color: AppColors.messier,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  fallback.reason,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _VisualEyepieceTable(
            telescopeName: combos.first.equipment.name,
            items: combos,
            isToday: isToday,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }
}

class _ImagingMetric extends StatelessWidget {
  const _ImagingMetric({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 88),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _CaptureSettingsGrid extends StatelessWidget {
  const _CaptureSettingsGrid({required this.equipmentId, required this.items});

  final String equipmentId;
  final List<CaptureModeRecommendation> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth = constraints.maxWidth >= 560 && items.length > 1
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '노출값은 장비 지원 범위 안의 시험 시작값이며 제조사 최적값이 아닙니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              key: ValueKey('equipment-capture-settings-$equipmentId'),
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: _CaptureModeCard(
                      key: ValueKey(
                        'equipment-capture-mode-$equipmentId-${item.modeId}',
                      ),
                      item: item,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CaptureModeCard extends StatelessWidget {
  const _CaptureModeCard({super.key, required this.item});

  final CaptureModeRecommendation item;

  @override
  Widget build(BuildContext context) {
    final exposureRecommendations = item.exposureRecommendations.isNotEmpty
        ? item.exposureRecommendations
        : [
            CaptureExposureRecommendation(
              purpose: CaptureExposurePurpose.standard,
              exposureSeconds: item.recommendedExposureSeconds,
              confidence: item.exposureConfidence,
              policyId: item.exposurePolicyId,
              reason: item.exposureReason,
              guidance: item.recommendedExposureSeconds == null
                  ? item.exposureSupportLabel
                  : null,
              inputs: item.exposureInputs,
            ),
          ];
    final gain = item.recommendedGain == null
        ? item.gainSupportLabel
        : _formatNumber(item.recommendedGain!);
    final filter = item.recommendedFilters.isNotEmpty
        ? item.recommendedFilters.join(', ')
        : item.supportedFilters.isNotEmpty
        ? '지원: ${item.supportedFilters.join(', ')}'
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.16),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.messier,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.usesSensorDerotation) ...[
                  const SizedBox(width: 6),
                  const Flexible(
                    child: Text(
                      '센서 회전 보정',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            for (final exposure in exposureRecommendations)
              _CaptureSettingDetail(
                label: exposure.purpose.label,
                value: exposure.exposureSeconds == null
                    ? exposure.guidance ?? item.exposureSupportLabel
                    : '${_formatNumber(exposure.exposureSeconds!)}초',
                confidence: exposure.confidence,
                reason: exposure.reason,
                inputs: exposure.inputs,
              ),
            for (final advisory in item.exposureAdvisories) ...[
              Text(
                '환경 · $advisory',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (gain != null)
              _CaptureSettingDetail(
                label: 'Gain',
                value: gain,
                confidence: item.gainConfidence,
                reason: item.gainReason,
                inputs: item.gainInputs,
              ),
            if (filter != null)
              _CaptureSettingDetail(
                label: '필터',
                value: filter,
                confidence: item.filterConfidence,
                reason: item.filterReason,
                inputs: item.filterInputs,
              ),
            for (final combination in item.channelCombinations)
              _CaptureSettingDetail(
                label: combination.name,
                value: combination.guidance,
                confidence: combination.confidence,
                reason: combination.reason,
                inputs: combination.inputs,
              ),
            for (final caution in item.cautions) ...[
              const SizedBox(height: 3),
              Text(
                '주의 · $caution',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

class _CaptureSettingDetail extends StatelessWidget {
  const _CaptureSettingDetail({
    required this.label,
    required this.value,
    required this.confidence,
    this.reason,
    this.inputs = const [],
  });

  final String label;
  final String value;
  final CaptureRecommendationConfidence confidence;
  final String? reason;
  final List<String> inputs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CaptureSettingLine(label: label, value: value),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 88),
              _CaptureConfidenceBadge(confidence: confidence),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 88),
              child: Text(
                reason!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ),
          ],
          if (inputs.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 88),
              child: Text(
                '입력 · ${inputs.join(' · ')}',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.78),
                  fontSize: 9,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureConfidenceBadge extends StatelessWidget {
  const _CaptureConfidenceBadge({required this.confidence});

  final CaptureRecommendationConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (confidence) {
      CaptureRecommendationConfidence.recommended => const Color(0xFF6EE7B7),
      CaptureRecommendationConfidence.experimental => const Color(0xFFFBBF24),
      CaptureRecommendationConfidence.unavailable => AppColors.textSecondary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          confidence.label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CaptureSettingLine extends StatelessWidget {
  const _CaptureSettingLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아이피스별 안시 추천을 가로 비교 표로 표시한다.
class _VisualEyepieceTable extends StatelessWidget {
  const _VisualEyepieceTable({
    required this.telescopeName,
    required this.items,
    required this.isToday,
  });

  final String telescopeName;
  final List<VisualEquipmentRecommendation> items;
  final bool isToday;

  static const _borderColor = Color(0x33FFFFFF);
  static const _headerColor = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    final bestScore = items
        .map((item) => item.score)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          telescopeName,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            const labelWidth = 44.0;
            final columnWidth = items.length <= 3
                ? (constraints.maxWidth - labelWidth) / items.length
                : 72.0;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Table(
                  columnWidths: {
                    0: const FixedColumnWidth(labelWidth),
                    for (var i = 0; i < items.length; i++)
                      i + 1: FixedColumnWidth(columnWidth),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder.all(color: _borderColor, width: 0.5),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: _headerColor),
                      children: [
                        const _TableLabelCell(''),
                        for (final item in items)
                          _TableHeaderCell(
                            item.eyepieceFocalLabel,
                            highlight: item.score >= bestScore,
                            feasibleToday: !isToday || item.isFeasibleToday,
                          ),
                      ],
                    ),
                    TableRow(
                      children: [
                        const _TableLabelCell('화면'),
                        for (final item in items)
                          _TableValueCell(
                            item.screenFillPercent > 0
                                ? '${item.screenFillPercent}%'
                                : '-',
                            muted: !item.isRecommended,
                            feasibleToday: !isToday || item.isFeasibleToday,
                          ),
                      ],
                    ),
                    TableRow(
                      children: [
                        const _TableLabelCell('배율'),
                        for (final item in items)
                          _TableValueCell(
                            item.magnification == null
                                ? '-'
                                : '약 ${item.magnification}배',
                            muted: !item.isRecommended,
                            feasibleToday: !isToday || item.isFeasibleToday,
                          ),
                      ],
                    ),
                    TableRow(
                      children: [
                        const _TableLabelCell('비고'),
                        for (final item in items)
                          _TableValueCell(
                            _noteFor(item),
                            muted: !item.isRecommended,
                            feasibleToday: !isToday || item.isFeasibleToday,
                            small: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (items.first.recommendedEyepieceFocalLabel.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '권장 아이피스 ${items.first.recommendedEyepieceFocalLabel}',
            key: ValueKey(
              'equipment-visual-ideal-eyepiece-${items.first.equipment.id}',
            ),
            style: const TextStyle(color: AppColors.messier, fontSize: 12),
          ),
        ],
      ],
    );
  }

  String _noteFor(VisualEquipmentRecommendation item) {
    if (isToday && item.isFeasibleToday) return '가능 · ${item.reason}';
    if (item.screenFillNote != null && item.screenFillNote!.isNotEmpty) {
      return item.screenFillNote!;
    }
    return item.reason;
  }
}

class _TableLabelCell extends StatelessWidget {
  const _TableLabelCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(
    this.text, {
    required this.highlight,
    required this.feasibleToday,
  });

  final String text;
  final bool highlight;
  final bool feasibleToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: feasibleToday
              ? (highlight ? AppColors.solar : AppColors.textPrimary)
              : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _TableValueCell extends StatelessWidget {
  const _TableValueCell(
    this.text, {
    required this.muted,
    required this.feasibleToday,
    this.small = false,
  });

  final String text;
  final bool muted;
  final bool feasibleToday;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = !feasibleToday
        ? AppColors.textSecondary.withValues(alpha: 0.55)
        : muted
        ? AppColors.textSecondary
        : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: small ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: small ? 10 : 12, height: 1.25),
      ),
    );
  }
}

/// 오늘 추천 전용 래퍼.
class TodayEquipmentRecommendationSection extends StatelessWidget {
  const TodayEquipmentRecommendationSection({
    super.key,
    required this.recommendation,
    this.onManageTap,
  });

  final TodayEquipmentRecommendation recommendation;
  final VoidCallback? onManageTap;

  @override
  Widget build(BuildContext context) {
    final objectRec = ObjectEquipmentRecommendation(
      imaging: recommendation.imaging != null
          ? [recommendation.imaging!]
          : const [],
      visual: recommendation.visual,
      hasRegisteredEquipment: recommendation.hasRegisteredEquipment,
      showImaging: recommendation.showImaging,
      showVisual: recommendation.showVisual,
      imagingAvailability: recommendation.imagingAvailability,
      visualAvailability: recommendation.visualAvailability,
    );

    return EquipmentRecommendationSection(
      recommendation: objectRec,
      isToday: true,
      onManageTap: onManageTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$icon $label',
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({this.onManageTap});

  final VoidCallback? onManageTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '추천 장비',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '등록된 장비가 없습니다',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (onManageTap != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onManageTap, child: const Text('장비 등록하기')),
            ],
          ],
        ),
      ),
    );
  }
}
