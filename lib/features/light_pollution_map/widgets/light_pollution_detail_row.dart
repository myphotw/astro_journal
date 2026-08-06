import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Label-aligned detail row for the location popup cards.
class LightPollutionDetailRow extends StatelessWidget {
  const LightPollutionDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 52,
    this.valueStyle,
  });

  static const double defaultLabelWidth = 52;

  final String label;
  final String value;
  final double labelWidth;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ??
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
