import 'package:astro_journal/core/theme/app_colors.dart';
import 'package:astro_journal/data/models/astronomy_event.dart';
import 'package:astro_journal/data/repositories/astronomy_event_repository.dart';
import 'package:astro_journal/features/home/view/widgets/astronomy_event_card.dart';
import 'package:astro_journal/features/home/view/widgets/astronomy_events_section.dart';
import 'package:astro_journal/features/home/viewmodel/astronomy_events_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('home projection handles 0, 1, 2, and 3+ event counts', () async {
    for (final count in [0, 1, 2, 3, 5]) {
      final repository = _FakeAstronomyEventRepository(_events(count));
      final viewModel = AstronomyEventsViewModel(repository);
      await viewModel.load();

      expect(viewModel.events, hasLength(count));
      expect(viewModel.homeEvents, hasLength(count > 3 ? 3 : count));
    }
  });

  testWidgets('home shows at most three cards and full list reuses state', (
    tester,
  ) async {
    final repository = _FakeAstronomyEventRepository(_events(5));
    final viewModel = AstronomyEventsViewModel(repository);

    await tester.pumpWidget(_testApp(viewModel));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('home-astronomy-events-section')), findsOne);
    expect(find.byType(AstronomyEventCard), findsNWidgets(3));
    expect(repository.calls, 1);

    await tester.tap(find.byKey(const Key('open-all-astronomy-events')));
    await tester.pumpAndSettle();

    expect(find.text('천문 이벤트'), findsOne);
    expect(find.byType(AstronomyEventCard), findsNWidgets(5));
    expect(repository.calls, 1);
  });

  testWidgets('event failure stays inside its section and retry recovers', (
    tester,
  ) async {
    final repository = _FakeAstronomyEventRepository(
      const <AstronomyEvent>[],
      error: StateError('offline'),
    );
    final viewModel = AstronomyEventsViewModel(repository);

    await tester.pumpWidget(_testApp(viewModel));
    await tester.pump();
    await tester.pump();

    expect(find.text('기존 Home 영역'), findsOne);
    expect(find.byKey(const Key('astronomy-events-error')), findsOne);

    repository
      ..error = null
      ..events = _events(1);
    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AstronomyEventCard), findsOne);
    expect(repository.calls, 2);
  });

  testWidgets('full list keeps backend order and groups events by local month', (
    tester,
  ) async {
    final localAugust = DateTime(2026, 8, 15, 12);
    final localSeptember = DateTime(2026, 9, 15, 12);
    final repository = _FakeAstronomyEventRepository([
      _eventAt('august-event', localAugust),
      _eventAt('september-event', localSeptember),
    ]);
    final viewModel = AstronomyEventsViewModel(repository);
    await viewModel.load();

    await tester.pumpWidget(_testApp(viewModel));
    await tester.tap(find.byKey(const Key('open-all-astronomy-events')));
    await tester.pumpAndSettle();

    expect(find.text('2026년 8월'), findsOne);
    expect(find.text('2026년 9월'), findsOne);
    final augustTop = tester.getTopLeft(
      find.byKey(const Key('astronomy-event-august-event')),
    );
    final septemberTop = tester.getTopLeft(
      find.byKey(const Key('astronomy-event-september-event')),
    );
    expect(augustTop.dy, lessThan(septemberTop.dy));
    expect(repository.calls, 1);
  });

  testWidgets('long title and tags remain bounded on a phone width', (
    tester,
  ) async {
    final event = AstronomyEvent(
      id: 'long',
      type: AstronomyEventType.planetViewing,
      title: '매우 긴 천문 이벤트 제목이 작은 화면에서도 두 줄을 넘지 않고 안전하게 표시됩니다',
      peakAt: DateTime.now().add(const Duration(days: 2)).toUtc(),
      tags: const [
        '아주 긴 첫 번째 관측 조건 태그입니다',
        '아주 긴 두 번째 관측 조건 태그입니다',
        '표시하지 않을 세 번째 태그',
      ],
      priority: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AppColors.background,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: AstronomyEventCard(event: event, now: DateTime.now()),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(event.tags[2]), findsNothing);
  });
}

Widget _testApp(AstronomyEventsViewModel viewModel) {
  return ChangeNotifierProvider.value(
    value: viewModel,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [Text('기존 Home 영역'), AstronomyEventsSection()],
          ),
        ),
      ),
    ),
  );
}

class _FakeAstronomyEventRepository implements AstronomyEventRepository {
  _FakeAstronomyEventRepository(this.events, {this.error});

  List<AstronomyEvent> events;
  Object? error;
  int calls = 0;

  @override
  Future<List<AstronomyEvent>> getUpcomingEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    calls += 1;
    final currentError = error;
    if (currentError != null) throw currentError;
    return events;
  }
}

List<AstronomyEvent> _events(int count) => List.generate(
  count,
  (index) => AstronomyEvent(
    id: 'event-$index',
    type: AstronomyEventType.values[index % 5],
    title: '이벤트 $index',
    peakAt: DateTime.now().add(Duration(days: index + 1)).toUtc(),
    tags: const ['맨눈', '도심'],
    priority: count - index,
  ),
);

AstronomyEvent _eventAt(String id, DateTime localDate) => AstronomyEvent(
  id: id,
  type: AstronomyEventType.conjunction,
  title: id,
  peakAt: localDate.toUtc(),
  tags: const [],
  priority: 1,
);
