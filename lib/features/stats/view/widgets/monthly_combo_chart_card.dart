import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/metadata_format.dart';
import '../../../../services/stats_models.dart';

class MonthlyComboChartCard extends StatefulWidget {
  const MonthlyComboChartCard({
    super.key,
    required this.monthlyStats,
    required this.currentMonth,
    required this.year,
    this.onMonthDetail,
  });

  final List<MonthlyStatsPoint> monthlyStats;
  final MonthlyHighlight currentMonth;
  final int year;
  final void Function(int month)? onMonthDetail;

  @override
  State<MonthlyComboChartCard> createState() => _MonthlyComboChartCardState();
}

class _MonthlyComboChartCardState extends State<MonthlyComboChartCard> {
  static const _leftAxisReserved = 42.0;
  static const _bottomAxisReserved = 22.0;

  int? _touchedIndex;
  int? _selectedIndex;

  bool _isHighlighted(int index) =>
      _touchedIndex == index || _selectedIndex == index;

  int? get _activeTooltipIndex => _touchedIndex ?? _selectedIndex;

  int? _indexFromDx(double dx, double chartWidth) {
    final plotWidth = chartWidth - _leftAxisReserved;
    if (dx < _leftAxisReserved || plotWidth <= 0) return null;
    final index =
        ((dx - _leftAxisReserved) / plotWidth * widget.monthlyStats.length)
            .floor();
    if (index < 0 || index >= widget.monthlyStats.length) return null;
    return index;
  }

  double _slotWidth(double chartWidth) =>
      (chartWidth - _leftAxisReserved) / widget.monthlyStats.length;

  void _handlePointer(Offset localPosition, double chartWidth, {required bool finalize}) {
    final index = _indexFromDx(localPosition.dx, chartWidth);
    if (index == null) {
      if (finalize) setState(() => _touchedIndex = null);
      return;
    }

    if (finalize) {
      HapticFeedback.lightImpact();
      setState(() {
        _selectedIndex = index;
        _touchedIndex = null;
      });
      return;
    }

    setState(() => _touchedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final maxIntegration = widget.monthlyStats
        .map((point) => point.integrationSeconds)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxCount = widget.monthlyStats
        .map((point) => point.shootCount)
        .fold<int>(0, (a, b) => a > b ? a : b);

    final integrationMax = maxIntegration <= 0 ? 1.0 : maxIntegration;
    final countMax = maxCount <= 0 ? 1 : maxCount;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.year}년 월별 촬영 통계',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _LegendDot(color: const Color(0xFF4DD0E1), label: '적산시간'),
                const SizedBox(width: 8),
                _LegendDot(color: const Color(0xFF7986CB), label: '촬영횟수'),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '월을 탭하면 요약이 표시됩니다 · 자세히 보기로 상세 통계 확인',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _SummaryChip(
                  label: '이번 달 적산',
                  value: MetadataFormat.formatSeconds(
                    widget.currentMonth.integrationSeconds,
                  ),
                ),
                _SummaryChip(
                  label: '이번 달 촬영',
                  value: '${widget.currentMonth.shootCount}회',
                ),
                _SummaryChip(
                  label: '이번 달 평균',
                  value: MetadataFormat.formatSeconds(
                    widget.currentMonth.averageIntegrationSeconds,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMd),
            if (_activeTooltipIndex != null) ...[
              _MonthSummaryBox(
                year: widget.year,
                point: widget.monthlyStats[_activeTooltipIndex!],
                onViewDetail: widget.onMonthDetail == null
                    ? null
                    : () => widget.onMonthDetail!(
                          widget.monthlyStats[_activeTooltipIndex!].month,
                        ),
              ),
              const SizedBox(height: AppTheme.spacingSm),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth = constraints.maxWidth;
                final slotWidth = _slotWidth(chartWidth);
                final highlightIndex = _activeTooltipIndex;
                final monthCount = widget.monthlyStats.length;
                final maxLineX =
                    monthCount <= 1 ? 1.0 : (monthCount - 1).toDouble();

                return SizedBox(
                  height: 220,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor:
                          const Color(0xFF4DD0E1).withValues(alpha: 0.18),
                      highlightColor:
                          const Color(0xFF4DD0E1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      onTapDown: (details) => _handlePointer(
                        details.localPosition,
                        chartWidth,
                        finalize: false,
                      ),
                      onTapUp: (details) => _handlePointer(
                        details.localPosition,
                        chartWidth,
                        finalize: true,
                      ),
                      onTapCancel: () => setState(() => _touchedIndex = null),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (highlightIndex != null)
                            Positioned(
                              left: _leftAxisReserved + slotWidth * highlightIndex,
                              width: slotWidth,
                              top: 4,
                              bottom: _bottomAxisReserved,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4DD0E1)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF4DD0E1)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                            ),
                          BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceBetween,
                              groupsSpace: 4,
                              maxY: integrationMax * 1.15,
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (value) => FlLine(
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.12),
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: _leftAxisReserved,
                                    getTitlesWidget: (value, meta) {
                                      if (value == meta.max ||
                                          value == meta.min) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        _formatAxisIntegration(value),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 9,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index < 0 ||
                                          index >=
                                              widget.monthlyStats.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final highlighted =
                                          _isHighlighted(index);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4),
                                        child: Text(
                                          widget.monthlyStats[index].label,
                                          style: TextStyle(
                                            color: highlighted
                                                ? AppColors.textPrimary
                                                : AppColors.textSecondary,
                                            fontSize: 9,
                                            fontWeight: highlighted
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              barGroups: [
                                for (var i = 0;
                                    i < widget.monthlyStats.length;
                                    i++)
                                  BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: widget.monthlyStats[i]
                                            .integrationSeconds,
                                        width: _isHighlighted(i) ? 14 : 10,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                        color: const Color(0xFF4DD0E1)
                                            .withValues(
                                          alpha: _isHighlighted(i) ? 1 : 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                              barTouchData: BarTouchData(enabled: false),
                            ),
                          ),
                          Positioned(
                            left: _leftAxisReserved,
                            top: 0,
                            right: 0,
                            bottom: _bottomAxisReserved,
                            child: LineChart(
                              LineChartData(
                                minX: 0,
                                maxX: maxLineX,
                                minY: 0,
                                maxY: countMax * 1.2,
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                lineTouchData: LineTouchData(enabled: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: [
                                      for (var i = 0;
                                          i < widget.monthlyStats.length;
                                          i++)
                                        FlSpot(
                                          i.toDouble(),
                                          widget.monthlyStats[i].shootCount
                                              .toDouble(),
                                        ),
                                    ],
                                    isCurved: true,
                                    color: const Color(0xFF7986CB),
                                    barWidth: _selectedIndex != null ? 3 : 2.5,
                                    dotData: FlDotData(
                                      show: true,
                                      getDotPainter:
                                          (spot, percent, bar, index) {
                                        final highlighted =
                                            _isHighlighted(index);
                                        return FlDotCirclePainter(
                                          radius: highlighted ? 6.5 : 3.5,
                                          color: highlighted
                                              ? const Color(0xFF9FA8DA)
                                              : const Color(0xFF7986CB),
                                          strokeWidth:
                                              highlighted ? 2.5 : 1.5,
                                          strokeColor: highlighted
                                              ? const Color(0xFF4DD0E1)
                                              : AppColors.background,
                                        );
                                      },
                                    ),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: const Color(0xFF7986CB)
                                          .withValues(alpha: 0.08),
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatAxisIntegration(double seconds) {
    if (seconds >= 3600) {
      return '${(seconds / 3600).toStringAsFixed(0)}h';
    }
    if (seconds >= 60) {
      return '${(seconds / 60).toStringAsFixed(0)}m';
    }
    return '${seconds.toStringAsFixed(0)}s';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthSummaryBox extends StatelessWidget {
  const _MonthSummaryBox({
    required this.year,
    required this.point,
    this.onViewDetail,
  });

  final int year;
  final MonthlyStatsPoint point;
  final VoidCallback? onViewDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF4DD0E1).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$year년 ${point.month}월',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onViewDetail != null)
                TextButton(
                  onPressed: onViewDetail,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('자세히 보기'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _TooltipRow(
            label: '적산시간',
            value: MetadataFormat.formatSeconds(point.integrationSeconds),
          ),
          const SizedBox(height: 2),
          _TooltipRow(
            label: '촬영횟수',
            value: '${point.shootCount}회',
          ),
        ],
      ),
    );
  }
}

class _TooltipRow extends StatelessWidget {
  const _TooltipRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
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
    );
  }
}
