import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/equipment_recommendation.dart';

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
    if (!recommendation.hasRegisteredEquipment) {
      return _EmptyCard(onManageTap: onManageTap);
    }

    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 12),
            if (recommendation.imaging.isNotEmpty) ...[
              _SectionHeader(icon: '📷', label: isToday ? '오늘 추천' : '촬영'),
              const SizedBox(height: 8),
              ...recommendation.imaging.map(_buildImagingRow),
            ] else ...[
              const _SectionHeader(icon: '📷', label: '촬영'),
              const SizedBox(height: 4),
              const Text(
                '등록된 촬영 장비가 없습니다',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _SectionHeader(icon: '👁', label: '안시'),
            const SizedBox(height: 8),
            if (recommendation.visual.isNotEmpty)
              _buildVisualSection(recommendation.visual)
            else
              const Text(
                '등록된 안시 장비가 없습니다',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagingRow(ImagingEquipmentRecommendation item) {
    final medal = switch (item.rank) {
      1 => '🥇 ',
      2 => '🥈 ',
      3 => '🥉 ',
      _ => '',
    };
    final stars = '${'★' * item.starCount}${'☆' * (5 - item.starCount)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$medal${item.equipment.name}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stars,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '화면의 ${item.screenFillPercent}%',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          if (item.screenFillNote != null) ...[
            const SizedBox(height: 2),
            Text(
              '(${item.screenFillNote})',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ] else if (item.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.reason,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisualSection(List<VisualEquipmentRecommendation> items) {
    final displayItems = isToday
        ? items
            .where((item) => item.isFeasibleToday && item.eyepiece != null)
            .toList()
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
      final combos = entry.value
          .where((item) => item.eyepiece != null)
          .toList()
        ..sort(
          (a, b) => b.eyepiece!.focalLengthMm.compareTo(
            a.eyepiece!.focalLengthMm,
          ),
        );

      if (combos.isEmpty) {
        final fallback = entry.value.first;
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${fallback.equipment.name} · ${fallback.reason}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
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
                        const _TableLabelCell('평가'),
                        for (final item in items)
                          _TableValueCell(
                            '${'★' * item.starCount}${'☆' * (5 - item.starCount)}',
                            muted: !item.isRecommended,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: small ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: small ? 10 : 12,
          height: 1.25,
        ),
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
    if (!recommendation.hasRegisteredEquipment) {
      return EquipmentRecommendationSection(
        recommendation: ObjectEquipmentRecommendation.empty,
        onManageTap: onManageTap,
      );
    }

    final objectRec = ObjectEquipmentRecommendation(
      imaging: recommendation.imaging != null
          ? [recommendation.imaging!]
          : const [],
      visual: recommendation.visual,
      hasRegisteredEquipment: true,
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
        padding: const EdgeInsets.all(16),
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
              TextButton(
                onPressed: onManageTap,
                child: const Text('장비 등록하기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
