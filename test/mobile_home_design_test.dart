import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/theme/pc_design.dart';
import 'package:astro_journal/data/models/astronomy_event.dart';
import 'package:astro_journal/data/models/catalog_equipment_chips.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/scheduler_models.dart';
import 'package:astro_journal/data/models/scored_observation_target.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/astronomy_event_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/home/view/home_screen.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/home/view/pc_home_screen.dart';
import 'package:astro_journal/features/home/view/widgets/shooting_plan_action_button.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:astro_journal/features/home/viewmodel/astronomy_events_view_model.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
import 'package:astro_journal/shared/widgets/app_file_image.dart';
import 'package:astro_journal/shared/widgets/observatory_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _equipment = Equipment(
  id: 'test-camera',
  name: '테스트 망원경과 촬영 장비 이름',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
  focalLengthMm: 250,
);

RecommendationResult _result(int number) => RecommendationResult(
  object: CatalogObject(
    id: 'NGC$number',
    name: '한국어가 포함된 매우 긴 촬영 대상 이름 $number',
    number: number,
    catalog: CatalogType.ngc,
    type: '은하',
    constellation: '-',
    ra: '-',
    dec: '-',
    magnitude: '-',
  ),
  reasons: const [],
  season: '촬영 시기',
  score: 75,
  moonSeparation: 54,
);

class _Sites extends Fake implements ObservationSiteRepository {
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}
}

class _Target extends Fake implements ScoredObservationTarget {
  @override
  ImagingSuitabilityAssessment? get imagingAssessment => null;
}

class _Slot extends Fake implements ScheduleItem {
  _Slot(this.result);
  @override
  final RecommendationResult result;
  @override
  CatalogObject get catalogObject => result.object;
  @override
  DateTime get startTime => DateTime(2026, 11, 20, 21);
  @override
  DateTime get endTime => DateTime(2026, 11, 20, 22);
  @override
  bool get hasTimeOverride => true;
  @override
  bool get isManual => true;
  @override
  String get durationLabel => '60분(권장 충족)';
  @override
  Duration get shootingDuration => endTime.difference(startTime);
  @override
  ScheduleItemStatus get status => ScheduleItemStatus.recommended;
  @override
  ScoredObservationTarget get target => _Target();
  @override
  int get starCount => 4;
}

class _Home extends ChangeNotifier implements HomeViewModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  final activeObservationSiteViewModel = ActiveObservationSiteViewModel(
    _Sites(),
  );
  @override
  final recommendedObjects = [_result(9981), _result(9982)];
  @override
  final activeEquipment = const [_equipment];
  @override
  TrackingMode trackingMode = TrackingMode.altAz;
  String? chosenEquipment;
  final plan = <String>{};
  int refreshCalls = 0;
  Future<void> changeDashboardSite(String name, int count) async {
    await activeObservationSiteViewModel.selectSavedSite(
      ObservationSite(
        id: name,
        name: name,
        latitude: 37,
        longitude: 127,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    recommendedObjects
      ..clear()
      ..addAll(List.generate(count, (i) => _result(9981 + i)));
    notifyListeners();
  }

  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  bool get isWeatherLoading => false;
  @override
  final observationCondition = const ObservationCondition(
    score: 68,
    siteName: '현재 위치',
    moon: MoonInfo(
      age: 10,
      illumination: .5,
      phaseName: '상현',
      phaseEmoji: '🌛',
    ),
  );
  @override
  ObservationContext? get lastSessionContext => null;
  @override
  List<RecommendationResult> get allRecommendedObjects => recommendedObjects;
  @override
  List<String> get exclusionReasons => const [];
  @override
  String? get scheduleEmptyMessage => null;
  @override
  List<ScheduleItem> get scheduleItems => [
    for (final result in recommendedObjects) _Slot(result),
  ];
  @override
  RecommendationComputationState get recommendationState =>
      RecommendationComputationState.current;
  @override
  ScheduleComputationState get scheduleState =>
      ScheduleComputationState.current;
  @override
  bool isPlanned(String objectId) => plan.contains(objectId);
  @override
  bool isScheduled(String objectId) => plan.contains(objectId);
  @override
  bool canAddToShootingPlan(String objectId) => true;
  @override
  String? userPhotoFor(CatalogObject object) => null;
  @override
  CatalogEquipmentChips todayEquipmentChipsFor(String objectId) =>
      const CatalogEquipmentChips(
        items: [
          CatalogEquipmentChipItem(label: '추천 장비', equipmentId: 'test-camera'),
        ],
      );
  @override
  Future<void> refresh() async => refreshCalls++;
  @override
  Future<void> finishDeferredHeavyWork() async {}
  @override
  Future<void> setEquipment(String? equipmentId) async {
    chosenEquipment = equipmentId;
  }

  @override
  Future<void> setTrackingMode(TrackingMode mode) async {
    trackingMode = mode;
    notifyListeners();
  }

  @override
  Future<void> toggleTonightPlan(String objectId) async {
    if (!plan.add(objectId)) plan.remove(objectId);
    notifyListeners();
  }

  @override
  void dispose() {
    activeObservationSiteViewModel.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets(
    'PC dashboard keeps rows aligned across sites and scrolls each list',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(2560, 1440);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final home = _Home();
      await home.changeDashboardSite('관측지 A', 2);
      final gallery = _DashboardGallery();
      final events = AstronomyEventsViewModel(_DashboardEvents());
      await events.load();
      addTearDown(home.dispose);
      addTearDown(gallery.dispose);
      addTearDown(events.dispose);

      final pane = ValueNotifier(const Size(1440, 900));
      addTearDown(pane.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeViewModel>.value(value: home),
            ChangeNotifierProvider<GalleryViewModel>.value(value: gallery),
            ChangeNotifierProvider<AstronomyEventsViewModel>.value(
              value: events,
            ),
          ],
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder(
                valueListenable: pane,
                builder: (_, size, body) => SizedBox(
                  width: size.width,
                  height: size.height,
                  child: body,
                ),
                child: const PcHomeScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final photos = find.byType(AppFileImage);
      final eventPanel = find.byKey(const Key('pc-home-astronomy-events'));
      final recommendations = find.byKey(
        const Key('pc-home-recommendations-panel'),
      );
      final schedules = find.byKey(const Key('pc-home-schedule-panel'));
      Finder panelFor(Finder content) =>
          find.ancestor(of: content, matching: find.byType(ObservatoryPanel));
      final panels = [
        panelFor(find.byKey(const Key('pc-home-astronomy-panel'))),
        panelFor(find.byKey(const Key('pc-home-hourly-weather-panel'))),
        panelFor(recommendations),
        panelFor(schedules),
        panelFor(photos.first),
        eventPanel,
      ];
      List<Rect> alignedRects() {
        final bounds = panels.map(tester.getRect).toList();
        final [status, weather, recommendation, schedule, photos, events] =
            bounds;
        expect(status.top, recommendation.top);
        expect(recommendation.top, schedule.top);
        expect(weather.bottom, recommendation.bottom);
        expect(recommendation.bottom, schedule.bottom);
        expect(photos.top, events.top);
        expect(photos.bottom, events.bottom);
        expect(photos.top, greaterThan(recommendation.bottom));
        return bounds;
      }

      final recommendation = find.byKey(
        const Key('pc-home-recommendation-NGC9981'),
      );
      final schedule = find.byKey(const Key('pc-home-schedule-NGC9981'));
      expect(photos, findsNWidgets(4));
      final compactPhoto = tester.getSize(photos.first);
      final compactEventPanel = tester.getSize(eventPanel);
      final compactRow = tester.getSize(recommendation);
      final compactSchedule = tester.getSize(schedule);
      alignedRects();
      expect(compactPhoto.width, 136);
      expect(tester.takeException(), isNull);

      pane.value = const Size(2368, 1358);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(photos.first).width,
        greaterThan(compactPhoto.width * 1.8),
      );
      expect(
        tester.getSize(eventPanel).height,
        greaterThan(compactEventPanel.height + 100),
      );
      expect(
        tester.getSize(recommendation).height,
        greaterThan(compactRow.height),
      );
      expect(
        tester.getSize(schedule).height,
        greaterThan(compactSchedule.height),
      );
      final eventBottom = tester.getBottomRight(eventPanel).dy;
      expect(eventBottom, inInclusiveRange(1030, 1358));
      final largePhoto = tester.getSize(photos.first);
      expect(largePhoto.aspectRatio, closeTo(1.24, .001));
      final photoContainer = panelFor(photos.first);
      expect(
        tester.getBottomRight(find.text('2026.11.15')).dy,
        lessThan(tester.getBottomRight(photoContainer).dy),
      );
      final sparseBounds = alignedRects();
      expect(find.text('관측 상태 및 지수'), findsOneWidget);
      expect(find.text('날씨 정보'), findsOneWidget);
      expect(
        find.byKey(const Key('open-all-astronomy-events')),
        findsOneWidget,
      );
      await tester.tap(find.text('촬영 계획 추가').first);
      await tester.pumpAndSettle();
      expect(home.plan, {'NGC9981'});
      expect(tester.takeException(), isNull);

      await home.changeDashboardSite('관측지 B', 19);
      await tester.pumpAndSettle();
      expect(find.text('관측지 · 관측지 B'), findsOneWidget);
      expect(alignedRects(), sparseBounds);
      Finder listIn(Finder panel) =>
          find.descendant(of: panel, matching: find.byType(ListView));
      final recommendationList = listIn(recommendations);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(recommendationList),
          scrollDelta: const Offset(0, 150),
        ),
      );
      await tester.pumpAndSettle();
      ScrollPosition positionOf(Finder list) => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position;
      expect(positionOf(recommendationList).pixels, greaterThan(0));
      for (final (list, lastItem) in [
        (recommendationList, 'pc-home-recommendation-NGC9999'),
        (listIn(schedules), 'pc-home-schedule-NGC9999'),
        (listIn(eventPanel), 'astronomy-event-dashboard-7'),
      ]) {
        final position = positionOf(list);
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.byKey(Key(lastItem)).hitTestable(), findsOneWidget);
        expect(alignedRects(), sparseBounds);
        position.jumpTo(0);
        await tester.pumpAndSettle();
      }

      await home.changeDashboardSite('관측지 C', 0);
      await tester.pumpAndSettle();
      expect(find.text('추천 가능한 대상이 없습니다.'), findsOneWidget);
      expect(find.text('배정된 촬영 스케줄이 없습니다.'), findsOneWidget);
      expect(alignedRects(), sparseBounds);
      await home.changeDashboardSite('관측지 A', 2);
      await tester.pumpAndSettle();
      expect(alignedRects(), sparseBounds);

      for (final size in [
        const Size(2240, 720),
        const Size(900, 1300),
        const Size(560, 620),
      ]) {
        pane.value = size;
        await tester.pumpAndSettle();
        expect(tester.getSize(photos.first).width, lessThanOrEqualTo(136));
        expect(tester.getSize(recommendation).height, compactRow.height);
        if (size.width >= 1100) {
          final before = alignedRects();
          await home.changeDashboardSite('관측지 B', 19);
          await tester.pumpAndSettle();
          expect(alignedRects(), before);
        } else {
          expect(
            find.byKey(const Key('pc-home-layout-narrow')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('compact mobile home shows recommendations before scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<HomeViewModel>(
        create: (_) => _Home(),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final summary = find.byKey(const Key('home-observation-summary'));
    final site = find.byKey(const Key('active-observation-site-card'));
    final equipment = find.byKey(const Key('home-equipment-card'));
    final first = find.byKey(const ValueKey('home-recommendation-NGC9981'));
    final second = find.byKey(const ValueKey('home-recommendation-NGC9982'));
    expect(tester.getSize(summary).height, lessThan(720 / 2));
    expect(tester.getSize(site).height, 48);
    expect(tester.getSize(equipment).height, 48);
    expect(tester.getTopLeft(site).dy, tester.getTopLeft(equipment).dy);
    expect(tester.getBottomRight(first).dy, lessThan(720));
    expect(second.hitTestable(), findsOneWidget);
    expect(tester.getSize(first).height, lessThan(145));

    await tester.tap(find.text('상세'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('관측지수 산정 근거'), findsOneWidget);
    await tester.tapAt(const Offset(5, 70));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile home wraps content and retains observing and plan actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final home = _Home();
      await tester.pumpWidget(
        ChangeNotifierProvider<HomeViewModel>(
          create: (_) => home,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold));
      expect(PcDesign.isMobileContent(context), isTrue);
      expect(Theme.of(context).scaffoldBackgroundColor, PcDesign.background);
      expect(find.text('천체 촬영 도우미'), findsOneWidget);
      expect(
        find.byKey(const Key('home-context-compact-layout')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('관측 정보 새로고침'));
      expect(home.refreshCalls, 1);
      final dropdown = find.byKey(const Key('home-equipment-selector'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('equipment-option-test-camera')));
      await tester.pumpAndSettle();
      expect(home.chosenEquipment, 'test-camera');
      await tester.ensureVisible(find.text('EQ'));
      await tester.tap(find.text('EQ'));
      await tester.pumpAndSettle();
      expect(home.trackingMode, TrackingMode.eq);

      final buttons = find.byType(ShootingPlanActionButton);
      expect(buttons, findsNWidgets(2));
      expect(
        tester.getTopLeft(buttons.at(0)).dy,
        lessThan(tester.getTopLeft(buttons.at(1)).dy),
      );
      await tester.ensureVisible(find.text('촬영 계획 추가').first);
      await tester.tap(find.text('촬영 계획 추가').first);
      await tester.pumpAndSettle();
      expect(home.plan, {'NGC9981'});
      expect(find.text('계획 등록됨'), findsOneWidget);
      expect(find.text('추천 장비'), findsNWidgets(2));
      expect(find.byTooltip('촬영 순서 편집'), findsOneWidget);
      expect(find.text('수기 등록 · 사용자 시간'), findsNWidgets(2));
      expect(find.byKey(const Key('open-month-planner')), findsOneWidget);
      expect(find.byKey(const Key('open-season-planner')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ScrollView && w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1000, 840);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(buttons.at(0)).dx,
        lessThan(tester.getTopLeft(buttons.at(1)).dx),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _DashboardGallery extends ChangeNotifier implements GalleryViewModel {
  @override
  bool get hasLoaded => true;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  CatalogObject? catalogObjectFor(String celestialObjectId) => null;
  @override
  List<ShootingRecord> get recentPhotoRecords => [
    for (var index = 0; index < 4; index++)
      ShootingRecord(
        id: 'photo-$index',
        celestialObjectId: 'Photo $index',
        photoUri: 'test-missing-photo-$index.jpg',
        capturedAt: DateTime(2026, 11, 15 - index),
        createdAt: DateTime(2026, 11, 15 - index),
      ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DashboardEvents implements AstronomyEventRepository {
  @override
  Future<List<AstronomyEvent>> getUpcomingEvents({
    DateTime? from,
    DateTime? to,
  }) async => [
    for (var index = 0; index < 8; index++)
      AstronomyEvent(
        id: 'dashboard-$index',
        type: AstronomyEventType.planetViewing,
        title: 'Event $index',
        tags: const [],
        priority: 1,
        peakAt: DateTime.utc(2027, 5, index + 1),
        endAt: DateTime.utc(2099),
      ),
  ];
}
