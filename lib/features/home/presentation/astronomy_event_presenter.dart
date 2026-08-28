import 'package:flutter/material.dart';

import '../../../data/models/astronomy_event.dart';

class AstronomyEventPresenter {
  const AstronomyEventPresenter._();

  static String categoryLabel(AstronomyEventType type) => switch (type) {
    AstronomyEventType.meteorShower => '유성우',
    AstronomyEventType.solarEclipse => '일식',
    AstronomyEventType.lunarEclipse => '월식',
    AstronomyEventType.planetViewing => '행성',
    AstronomyEventType.conjunction => '근접',
    AstronomyEventType.unknown => '천문 이벤트',
  };

  static IconData categoryIcon(AstronomyEventType type) => switch (type) {
    AstronomyEventType.meteorShower => Icons.auto_awesome,
    AstronomyEventType.solarEclipse => Icons.wb_sunny_outlined,
    AstronomyEventType.lunarEclipse => Icons.nightlight_round,
    AstronomyEventType.planetViewing => Icons.public,
    AstronomyEventType.conjunction => Icons.compare_arrows,
    AstronomyEventType.unknown => Icons.event_outlined,
  };

  static DateTime? primaryInstant(AstronomyEvent event) =>
      event.peakAt ?? event.startAt ?? event.endAt;

  static bool isActive(AstronomyEvent event, DateTime now) {
    final start = event.startAt;
    final end = event.endAt;
    if (start == null || end == null) return false;

    final utcNow = now.toUtc();
    final hasStarted = !utcNow.isBefore(start);
    final hasNotEnded = utcNow.isBefore(end);
    final peakHasPassed =
        event.peakAt == null || !utcNow.isBefore(event.peakAt!);
    return hasStarted && hasNotEnded && peakHasPassed;
  }

  static String? countdownLabel(AstronomyEvent event, DateTime now) {
    if (isActive(event, now)) return '활동 중';

    final target = primaryInstant(event)?.toLocal();
    if (target == null) return null;
    final localNow = now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    final days = targetDay.difference(today).inDays;
    if (days == 0) return '오늘';
    if (days > 0) return 'D-$days';
    return null;
  }

  static String dateLabel(AstronomyEvent event, DateTime now) {
    final primary = primaryInstant(event);
    if (primary == null) return '일정 확인 중';
    final formatted = formatLocalDate(primary, now: now);
    if (event.type == AstronomyEventType.meteorShower && event.peakAt != null) {
      return '최대 활동 $formatted';
    }
    return formatted;
  }

  static String formatLocalDate(DateTime value, {required DateTime now}) {
    final local = value.toLocal();
    final localNow = now.toLocal();
    final date = '${local.month}월 ${local.day}일';
    return local.year == localNow.year ? date : '${local.year}년 $date';
  }

  static String monthGroupLabel(AstronomyEvent event) {
    final local = primaryInstant(event)?.toLocal();
    return local == null ? '일정 미정' : '${local.year}년 ${local.month}월';
  }
}
