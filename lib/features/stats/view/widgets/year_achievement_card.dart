import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/metadata_format.dart';
import '../../../../services/stats_models.dart';

class YearAchievementCard extends StatelessWidget {
  const YearAchievementCard({
    super.key,
    required this.summary,
    required this.availableYears,
    required this.selectedYear,
    required this.onYearChanged,
  });

  final YearAchievementSummary summary;
  final List<int> availableYears;
  final int selectedYear;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
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
                    '${summary.year}년의 성과',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                _YearSelector(
                  years: availableYears,
                  selectedYear: selectedYear,
                  onChanged: onYearChanged,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMd),
            _RowItem(
              label: '신규 촬영 대상 수',
              value: '${summary.newTargetCount}개',
            ),
            const Divider(height: 20, color: Color(0x33FFFFFF)),
            _RowItem(
              label: '총 적산시간',
              value: MetadataFormat.formatSeconds(summary.totalIntegrationSeconds),
            ),
            const Divider(height: 20, color: Color(0x33FFFFFF)),
            _RowItem(
              label: '가장 많이 촬영한 대상',
              value: summary.mostShotTarget ?? '-',
            ),
            const Divider(height: 20, color: Color(0x33FFFFFF)),
            _RowItem(
              label: '최장 적산 대상',
              value: summary.longestIntegrationTarget ?? '-',
            ),
          ],
        ),
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selectedYear,
    required this.onChanged,
  });

  final List<int> years;
  final int selectedYear;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (years.length <= 1) {
      return Text(
        '$selectedYear년',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selectedYear,
        isDense: true,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        dropdownColor: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        items: [
          for (final year in years)
            DropdownMenuItem<int>(
              value: year,
              child: Text('$year년'),
            ),
        ],
        onChanged: (year) {
          if (year != null) onChanged(year);
        },
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
