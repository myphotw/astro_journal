import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/hourly_weather_slot.dart';
import '../models/location_weather_info.dart';
import 'light_pollution_detail_row.dart';
import 'light_pollution_observation_index.dart';

class LightPollutionWeatherTab extends StatelessWidget {
  const LightPollutionWeatherTab({
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
        height: 56,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Text(
        errorMessage!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.solar, fontSize: 10),
      );
    }

    final info = weatherInfo;
    if (info == null) {
      return const Text(
        '기상 정보 없음',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LightPollutionObservationIndexSection(
          weatherInfo: info,
          isLoading: false,
        ),
        const SizedBox(height: 4),
        LightPollutionDetailRow(
          label: '기온',
          value: '${info.temperature.round()}°C',
        ),
        LightPollutionDetailRow(
          label: '구름',
          value: '${info.cloudCoverage}%',
        ),
        LightPollutionDetailRow(
          label: '강수',
          value: '${info.precipitationProbability.round()}%',
        ),
        LightPollutionDetailRow(
          label: '풍속',
          value: '${info.windSpeed.toStringAsFixed(1)}m/s',
        ),
        if (info.hourlySlots.isNotEmpty) ...[
          const SizedBox(height: 4),
          const Text(
            '시간대별',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          _HourlyWeatherStrip(slots: info.hourlySlots),
        ],
      ],
    );
  }
}

class _HourlyWeatherStrip extends StatelessWidget {
  const _HourlyWeatherStrip({required this.slots});

  final List<HourlyWeatherSlot> slots;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) => _HourlyWeatherChip(slot: slots[index]),
      ),
    );
  }
}

class _HourlyWeatherChip extends StatelessWidget {
  const _HourlyWeatherChip({required this.slot});

  final HourlyWeatherSlot slot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            slot.hourLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
            ),
          ),
          Text(
            slot.weatherEmoji,
            style: const TextStyle(fontSize: 11, height: 1.1),
          ),
          Text(
            '${slot.temperature.round()}°',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            slot.starsText,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(
              color: AppColors.solar,
              fontSize: 7,
              height: 1.1,
            ),
          ),
          Text(
            '구름 ${slot.cloudCoverage}%',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              height: 1.15,
            ),
          ),
          Text(
            '강수 ${slot.precipitationProbability.round()}%',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
