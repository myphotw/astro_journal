import 'package:astro_journal/data/models/astronomy_event.dart';
import 'package:astro_journal/features/home/presentation/astronomy_event_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps every backend type to a user-facing category', () {
    expect(
      AstronomyEventPresenter.categoryLabel(AstronomyEventType.meteorShower),
      '유성우',
    );
    expect(
      AstronomyEventPresenter.categoryLabel(AstronomyEventType.solarEclipse),
      '일식',
    );
    expect(
      AstronomyEventPresenter.categoryLabel(AstronomyEventType.lunarEclipse),
      '월식',
    );
    expect(
      AstronomyEventPresenter.categoryLabel(AstronomyEventType.planetViewing),
      '행성',
    );
    expect(
      AstronomyEventPresenter.categoryLabel(AstronomyEventType.conjunction),
      '근접',
    );
    expect(
      AstronomyEventPresenter.categoryIcon(AstronomyEventType.meteorShower),
      Icons.auto_awesome,
    );
    expect(
      AstronomyEventPresenter.categoryIcon(AstronomyEventType.solarEclipse),
      Icons.wb_sunny_outlined,
    );
    expect(
      AstronomyEventPresenter.categoryIcon(AstronomyEventType.lunarEclipse),
      Icons.nightlight_round,
    );
    expect(
      AstronomyEventPresenter.categoryIcon(AstronomyEventType.planetViewing),
      Icons.public,
    );
    expect(
      AstronomyEventPresenter.categoryIcon(AstronomyEventType.conjunction),
      Icons.compare_arrows,
    );
  });

  test('uses local calendar dates for today and tomorrow countdowns', () {
    final now = DateTime.now();
    final localToday = DateTime(now.year, now.month, now.day, 12);
    final localTomorrow = DateTime(now.year, now.month, now.day + 1, 12);

    expect(
      AstronomyEventPresenter.countdownLabel(
        _event(peakAt: localToday.toUtc()),
        now,
      ),
      '오늘',
    );
    expect(
      AstronomyEventPresenter.countdownLabel(
        _event(peakAt: localTomorrow.toUtc()),
        now,
      ),
      'D-1',
    );
  });

  test('uses a future peak after start and shows active after peak', () {
    final now = DateTime.now();
    final futurePeak = DateTime(now.year, now.month, now.day + 1, 12);
    final futureEvent = _event(
      startAt: now.subtract(const Duration(hours: 1)).toUtc(),
      peakAt: futurePeak.toUtc(),
      endAt: futurePeak.add(const Duration(days: 1)).toUtc(),
    );
    expect(AstronomyEventPresenter.countdownLabel(futureEvent, now), 'D-1');

    final activeEvent = _event(
      startAt: now.subtract(const Duration(hours: 2)).toUtc(),
      peakAt: now.subtract(const Duration(minutes: 10)).toUtc(),
      endAt: now.add(const Duration(hours: 2)).toUtc(),
    );
    expect(AstronomyEventPresenter.countdownLabel(activeEvent, now), '활동 중');
  });

  test('omits current year and includes a different year', () {
    final now = DateTime(2026, 8, 28);
    expect(
      AstronomyEventPresenter.formatLocalDate(
        DateTime(2026, 9, 1).toUtc(),
        now: now,
      ),
      '9월 1일',
    );
    expect(
      AstronomyEventPresenter.formatLocalDate(
        DateTime(2027, 1, 3).toUtc(),
        now: now,
      ),
      '2027년 1월 3일',
    );
  });

  test('meteor shower peak date receives the maximum activity prefix', () {
    final event = _event(
      type: AstronomyEventType.meteorShower,
      peakAt: DateTime(2026, 9, 1).toUtc(),
    );
    expect(
      AstronomyEventPresenter.dateLabel(event, DateTime(2026, 8, 28)),
      '최대 활동 9월 1일',
    );
  });
}

AstronomyEvent _event({
  AstronomyEventType type = AstronomyEventType.conjunction,
  DateTime? startAt,
  DateTime? peakAt,
  DateTime? endAt,
}) => AstronomyEvent(
  id: 'event',
  type: type,
  title: '이벤트',
  startAt: startAt,
  peakAt: peakAt,
  endAt: endAt,
  tags: const [],
  priority: 1,
);
