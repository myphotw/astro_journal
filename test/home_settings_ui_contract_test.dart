import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home = File(
    'lib/features/home/view/home_screen.dart',
  ).readAsStringSync();
  final settings = File(
    'lib/features/settings/view/settings_screen.dart',
  ).readAsStringSync();
  final recommendationSettings = File(
    'lib/features/settings/view/recommendation_settings_screen.dart',
  ).readAsStringSync();
  final navigation = File(
    'lib/shared/widgets/main_shell.dart',
  ).readAsStringSync();
  final homeViewModel = File(
    'lib/features/home/viewmodel/home_view_model.dart',
  ).readAsStringSync();

  test('home keeps the four requested information layers in order', () {
    final condition = home.indexOf('_ObservationIndexCard(');
    final recommendations = home.indexOf('오늘 밤 추천');
    final schedule = home.indexOf('_ObservationSessionTimeline(');
    final future = home.indexOf('_FuturePlanningSection(');

    expect(condition, greaterThanOrEqualTo(0));
    expect(recommendations, greaterThan(condition));
    expect(schedule, greaterThan(recommendations));
    expect(future, greaterThan(schedule));
  });

  test('observation score precedes compact shooting context controls', () {
    final score = home.indexOf("Key('home-observation-score')");
    final status = home.indexOf("Key('home-observation-status')");
    final detail = home.indexOf("label: const Text('상세')");
    final contextSection = home.indexOf(
      "Key('home-observation-context-section')",
    );

    expect(score, greaterThanOrEqualTo(0));
    expect(status, greaterThan(score));
    expect(detail, greaterThan(status));
    expect(contextSection, greaterThan(detail));
    expect(home, contains("'촬영 조건'"));
  });

  test('home removes peer recommendation tabs and category progress block', () {
    expect(home, isNot(contains("label: Text('추천 대상'")));
    expect(home, isNot(contains("label: Text('추천 장비'")));
    expect(home, isNot(contains('카테고리별 진행 현황')));
  });

  test(
    'recommendation wording describes suitability rather than probability',
    () {
      expect(home, contains('촬영 적합도'));
      expect(home, isNot(contains("'성공률'")));
    },
  );

  test('recommendations keep the existing two-column text card structure', () {
    expect(home, contains('for (var i = 0; i < items.length; i += 2)'));
    expect(home, contains('class _RecommendCompactCard'));
    expect(home, contains('gradient: LinearGradient'));
  });

  test('future planning exposes monthly and seasonal entries', () {
    expect(home, contains('월별 촬영 대상'));
    expect(home, contains('계절별 촬영 대상'));
    expect(home, contains('SeasonPlannerViewMode.byMonth'));
    expect(home, contains('SeasonPlannerViewMode.bySeason'));
  });

  test(
    'site equipment and tracking changes reuse recommendation scheduling',
    () {
      expect(homeViewModel, contains('Future<void> setEquipment('));
      expect(homeViewModel, contains('Future<void> setTrackingMode('));
      expect(homeViewModel, contains('Future<void> refreshForActiveSite()'));
      expect(homeViewModel, contains('await _applyRecommendations('));
      expect(homeViewModel, contains('_schedulerEngine.buildSchedule('));
    },
  );

  test('settings removes global environment inputs', () {
    expect(settings, isNot(contains('기준 Bortle 등급')));
    expect(recommendationSettings, isNot(contains('관측 가능 방위각')));
    expect(recommendationSettings, isNot(contains('시작 방위각')));
    expect(recommendationSettings, isNot(contains('종료 방위각')));
    expect(recommendationSettings, isNot(contains('관측 가능 고도')));
    expect(recommendationSettings, isNot(contains('최소 고도')));
    expect(recommendationSettings, isNot(contains('최대 고도')));
  });

  test('general settings tree contains no developer tools', () {
    expect(settings, isNot(contains('개발자 옵션')));
    expect(settings, isNot(contains('메타데이터 보기')));
    expect(settings, isNot(contains('EXIF 디버그')));
  });

  test('settings retains user data and observation management entries', () {
    expect(settings, contains('추천 필터 설정'));
    expect(recommendationSettings, contains('추천 카탈로그'));
    expect(recommendationSettings, contains('추천 우선순위'));
    expect(settings, contains('관측지 관리'));
    expect(settings, contains('장비 등록·관리'));
    expect(settings, contains('백업 내보내기'));
    expect(settings, contains('백업 가져오기'));
    expect(settings, contains('AstroJournalResetSection'));
    expect(settings, contains('TcBackendSettingsSection'));
    expect(settings.toLowerCase(), isNot(contains('api key')));
  });

  test('bottom navigation structure remains six screens plus photo action', () {
    expect('NavigationDestination('.allMatches(navigation), hasLength(7));
    expect(navigation, contains("'사진 등록'"));
    expect("label: '통계'".allMatches(navigation), hasLength(1));
  });
}
