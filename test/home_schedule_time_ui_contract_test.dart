import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home = File(
    'lib/features/home/view/home_screen.dart',
  ).readAsStringSync();
  final assessment = File(
    'lib/data/models/imaging_suitability_assessment.dart',
  ).readAsStringSync();
  final window = File(
    'lib/data/models/object_observation_window.dart',
  ).readAsStringSync();
  final scheduler = File(
    'lib/services/scheduler_engine.dart',
  ).readAsStringSync();
  final reasonBuilder = File(
    'lib/services/recommendation/recommendation_reason_builder.dart',
  ).readAsStringSync();

  test('schedule card reads FilterMode from the existing result assessment', () {
    expect(home, contains('item.result.imagingAssessment?.filterMode'));
    expect(home, contains("'schedule-filter-"));
    expect(home, contains("label: '필터 \${filterMode.label}'"));
  });

  test('detail exposes the three distinct shooting-time concepts', () {
    expect(home, contains("title: '최적 촬영 구간'"));
    expect(home, contains("title: '스케줄 배정'"));
    expect(home, contains("title: '적분시간 (최소 / 권장)'"));
    expect(home, contains('다른 촬영 대상까지 고려해 오늘 밤 실제 배정된 시간입니다.'));
    expect(home, contains('좋은 결과를 얻기 위한 이 대상의 일반적인 총 촬영량입니다.'));
  });

  test('optimal interval has one source-of-truth resolution path', () {
    expect(home, contains('preferred?.todayStartTime'));
    expect(home, contains('preferred?.todayEndTime'));
    expect(home, contains('window?.optimalStartTime'));
    expect(home, contains('window?.optimalEndTime'));
    expect(home, contains('여러 날 촬영해도 비슷한 구도를 유지하기 좋은 시간입니다.'));
    expect(assessment, contains('final DateTime? todayStartTime;'));
    expect(assessment, contains('final DateTime? todayEndTime;'));
  });

  test('duplicate and ambiguous time labels are not rendered', () {
    expect(home, isNot(contains("label: '추천 시작'")));
    expect(home, isNot(contains("label: '총 관측 시간'")));
    expect(home, isNot(contains("label: '오늘 권장 촬영'")));
    expect(home, isNot(contains("label: '총 권장 촬영'")));
    expect(reasonBuilder, isNot(contains('추천 촬영시간')));
  });

  test('integration and internal window contracts remain available', () {
    expect(home, contains('recommended.minimumExposure'));
    expect(home, contains('recommended.recommendedExposure'));
    expect(window, contains('final DateTime? recommendStartTime;'));
    expect(window, contains('final int totalObservableMinutes;'));
    expect(assessment, contains('final Duration? recommendedDailyExposure;'));
    expect(scheduler, contains('Duration(minutes: 10)'));
  });
}
