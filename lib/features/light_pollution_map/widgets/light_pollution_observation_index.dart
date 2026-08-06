import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/location_weather_info.dart';
import 'light_pollution_detail_row.dart';

/// Selected-location observation index (same logic as home screen).
class LightPollutionObservationIndexSection extends StatelessWidget {
  const LightPollutionObservationIndexSection({
    super.key,
    required this.weatherInfo,
    required this.isLoading,
    this.errorMessage,
  });

  final LocationWeatherInfo? weatherInfo;
  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Text(
        errorMessage!,
        maxLines: 3,
        style: const TextStyle(
          color: AppColors.solar,
          fontSize: 10,
          height: 1.35,
        ),
      );
    }

    final info = weatherInfo;
    if (info == null) {
      return const Text(
        '관측지수 정보 없음',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          height: 1.35,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusMessage(info: info),
        const SizedBox(height: 4),
        _ObservationIndexRow(info: info),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.info});

  final LocationWeatherInfo info;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          info.statusEmoji,
          style: const TextStyle(fontSize: 11, height: 1.35),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            info.statusMessageText,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _ObservationIndexRow extends StatelessWidget {
  const _ObservationIndexRow({required this.info});

  final LocationWeatherInfo info;

  @override
  Widget build(BuildContext context) {
    final value = info.isObservationFeasible
        ? '${info.observationScore} / 100  ${info.starsText}'
        : info.starsText;

    return LightPollutionDetailRow(
      label: '관측지수',
      value: value,
      valueStyle: TextStyle(
        color: info.isObservationFeasible
            ? _scoreColor(info.observationScore)
            : AppColors.solar,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );
  }

  static Color _scoreColor(int score) {
    if (score >= 90) return AppColors.ic;
    if (score >= 75) return const Color(0xFF60A5FA);
    if (score >= 60) return AppColors.solar;
    if (score >= 40) return const Color(0xFFFB923C);
    return const Color(0xFFEF4444);
  }
}
