import 'package:astro_journal/features/home/view/home_screen.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNotice(
    WidgetTester tester, {
    required RecommendationComputationState state,
    bool showingPreviousResults = false,
    String? message,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRecommendationRefreshNotice(
            state: state,
            showingPreviousResults: showingPreviousResults,
            message: message,
          ),
        ),
      ),
    );
  }

  testWidgets('recalculating explains that previous results remain visible', (
    tester,
  ) async {
    await pumpNotice(
      tester,
      state: RecommendationComputationState.recalculating,
      showingPreviousResults: true,
    );

    expect(
      find.byKey(const Key('home-recommendation-recalculating')),
      findsOneWidget,
    );
    expect(find.text('재계산 중입니다…'), findsOneWidget);
    expect(find.textContaining('기존 추천 결과'), findsOneWidget);
  });

  testWidgets('recalculating without results explains fresh calculation', (
    tester,
  ) async {
    await pumpNotice(
      tester,
      state: RecommendationComputationState.recalculating,
    );

    expect(find.textContaining('추천 대상을 계산'), findsOneWidget);
  });

  testWidgets('failed state shows a recommendation-scoped error', (
    tester,
  ) async {
    await pumpNotice(
      tester,
      state: RecommendationComputationState.failed,
      message: '추천을 다시 계산하지 못했습니다.',
    );

    expect(find.byKey(const Key('home-recommendation-failed')), findsOneWidget);
    expect(find.text('추천 계산에 실패했습니다.'), findsOneWidget);
    expect(find.text('추천을 다시 계산하지 못했습니다.'), findsOneWidget);
  });

  for (final entry in <ScheduleComputationState, String>{
    ScheduleComputationState.recalculating: '촬영 스케줄 계산 중…',
    ScheduleComputationState.current: '현재 조건 기준',
    ScheduleComputationState.failed: '계산 실패',
  }.entries) {
    testWidgets('schedule ${entry.key.name} status is visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HomeScheduleComputationStatus(state: entry.key)),
        ),
      );

      expect(
        find.byKey(Key('home-schedule-${entry.key.name}')),
        findsOneWidget,
      );
      expect(find.textContaining(entry.value), findsOneWidget);
    });
  }
}
