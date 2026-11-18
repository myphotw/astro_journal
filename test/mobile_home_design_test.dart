import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/core/theme/pc_design.dart';
import 'package:astro_journal/data/models/catalog_equipment_chips.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/data/models/scheduler_models.dart';
import 'package:astro_journal/data/models/scored_observation_target.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/home/view/home_screen.dart';
import 'package:astro_journal/features/home/view/widgets/shooting_plan_action_button.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:astro_journal/features/observation_site/viewmodel/active_observation_site_view_model.dart';
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

class _Sites extends Fake implements ObservationSiteRepository {}

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
