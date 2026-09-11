import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/multi_night_framing_reference.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/multi_night_framing_reference_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/catalog/widgets/multi_night_framing_section.dart';
import 'package:astro_journal/services/multi_night_framing_match_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no reference shows exact registration UX and manual time help', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeReferenceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('같은 구도 이어찍기'), findsOneWidget);
    expect(find.text('기준 구도 등록'), findsOneWidget);
    await tester.tap(find.byKey(const Key('multi-night-register-button')));
    await tester.pumpAndSettle();
    expect(find.text('실제 촬영 시작 날짜'), findsOneWidget);
    expect(find.text('실제 촬영 시작 시각'), findsOneWidget);
    expect(find.text('사진 등록 시간이 아닌 실제 촬영을 시작한 시간을 입력하세요.'), findsOneWidget);
    expect(find.text('M16'), findsOneWidget);
  });

  testWidgets('existing reference shows selectors and inline result', (
    tester,
  ) async {
    final matchService = _StubMatchService();
    await tester.pumpWidget(
      _app(_FakeReferenceRepository([_reference]), matchService: matchService),
    );
    await tester.pumpAndSettle();

    expect(find.text('기준'), findsOneWidget);
    expect(find.text('기준 변경'), findsOneWidget);
    expect(find.textContaining('Draco'), findsWidgets);
    expect(find.textContaining('집'), findsWidgets);
    expect(find.byKey(const Key('multi-night-inline-result')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('천문박명'), findsNothing);
    expect(matchService.calls, 1);
  });

  testWidgets('registration stores a target-fixed calculated reference', (
    tester,
  ) async {
    final repository = _FakeReferenceRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('multi-night-register-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('multi-night-save-button')));
    await tester.pumpAndSettle();

    expect(repository.values, hasLength(1));
    expect(repository.values.single.catalogObjectId, 'M16');
    expect(repository.values.single.equipmentId, 'draco');
    expect(repository.values.single.siteId, 'home');
    expect(find.byKey(const Key('multi-night-inline-result')), findsOneWidget);
  });

  testWidgets('different equipment without reference shows required message', (
    tester,
  ) async {
    final repository = _FakeReferenceRepository([_reference]);
    await tester.pumpWidget(_app(repository, equipment: [_draco, _seestar]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('multi-night-find-equipment')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seestar').last);
    await tester.pumpAndSettle();

    expect(find.text('선택한 장비에는 등록된 기준 구도가 없습니다.'), findsOneWidget);
  });

  testWidgets(
    'available result stays inline and is not recalculated by rebuilds',
    (tester) async {
      final service = _StubMatchService();
      await tester.pumpWidget(
        _app(
          _FakeReferenceRepository([_reference]),
          matchService: service,
          optimalWindowStart: DateTime(2026, 8, 4, 20),
          optimalWindowEnd: DateTime(2026, 8, 4, 21),
          optimalWindowSiteId: 'home',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('오늘 같은 구도로 촬영할 수 있습니다.'), findsOneWidget);
      expect(
        find.byKey(const Key('multi-night-inline-result')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('추천 촬영시간과도 잘 맞습니다.'), findsOneWidget);
      expect(service.calls, 1);

      await tester.pump();
      expect(service.calls, 1);
    },
  );

  testWidgets('bright-time result uses natural inline guidance', (
    tester,
  ) async {
    final service = _StubMatchService(
      cause: MultiNightFramingUnavailableCause.skyTooBright,
    );
    await tester.pumpWidget(
      _app(_FakeReferenceRepository([_reference]), matchService: service),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘은 같은 구도로 촬영하기 어렵습니다.'), findsOneWidget);
    expect(find.text('같은 구도가 되는 시간에는 아직 하늘이 밝습니다.'), findsOneWidget);
    expect(find.text('20:00 이후 촬영을 권장합니다.'), findsOneWidget);
    expect(find.textContaining('천문박명'), findsNothing);
  });

  testWidgets('site obstruction is explained in the inline result', (
    tester,
  ) async {
    final service = _StubMatchService(
      cause: MultiNightFramingUnavailableCause.obstructed,
    );
    await tester.pumpWidget(
      _app(_FakeReferenceRepository([_reference]), matchService: service),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 관측지에서 가려지는 방향입니다.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('changing the site recalculates once inside the card', (
    tester,
  ) async {
    final service = _StubMatchService();
    await tester.pumpWidget(
      _app(
        _FakeReferenceRepository([_reference]),
        matchService: service,
        sites: [_site, _site2],
      ),
    );
    await tester.pumpAndSettle();
    expect(service.calls, 1);

    await tester.tap(find.byKey(const Key('multi-night-find-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('외곽').last);
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(find.byKey(const Key('multi-night-inline-result')), findsOneWidget);
  });
}

Widget _app(
  _FakeReferenceRepository repository, {
  List<Equipment> equipment = const [_draco],
  MultiNightFramingMatchService? matchService,
  DateTime? optimalWindowStart,
  DateTime? optimalWindowEnd,
  String? optimalWindowSiteId,
  List<ObservationSite> sites = const [],
}) => MaterialApp(
  home: Scaffold(
    body: MultiNightFramingSection(
      object: _m16,
      repository: repository,
      equipmentRepository: _FakeEquipmentRepository(equipment),
      observationSiteRepository: _FakeSiteRepository(
        sites.isEmpty ? [_site] : sites,
      ),
      matchService:
          matchService ??
          MultiNightFramingMatchService(
            darkWindowResolver: _wholeDayDarkWindow,
          ),
      optimalWindowStart: optimalWindowStart,
      optimalWindowEnd: optimalWindowEnd,
      optimalWindowSiteId: optimalWindowSiteId,
    ),
  ),
);

MultiNightDarkWindow _wholeDayDarkWindow(DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  return (nightStart: start, nightEnd: start.add(const Duration(days: 1)));
}

class _StubMatchService extends MultiNightFramingMatchService {
  _StubMatchService({this.cause});

  final MultiNightFramingUnavailableCause? cause;
  int calls = 0;

  @override
  MultiNightFramingMatchResult findToday({
    required CatalogObject object,
    required MultiNightFramingReference reference,
    required ObservationSite site,
    required Equipment equipment,
    DateTime? today,
    DateTime? now,
    List<MultiNightDarkWindow>? darkWindows,
  }) {
    calls++;
    final unavailableCause = cause;
    if (unavailableCause != null) {
      return MultiNightFramingMatchResult(
        reference: reference,
        site: site,
        equipment: equipment,
        isAvailable: false,
        framingMatchAt: DateTime(2026, 8, 4, 17, 36),
        darkStart:
            unavailableCause == MultiNightFramingUnavailableCause.skyTooBright
            ? DateTime(2026, 8, 4, 20)
            : null,
        hourAngleDeg: -20,
        parallacticAngleDeg: 15,
        parallacticAngleDifferenceDeg: 0,
        altitudeDeg: 30,
        azimuthDeg: 180,
        unavailableCause: unavailableCause,
        unavailableReason:
            unavailableCause == MultiNightFramingUnavailableCause.skyTooBright
            ? '같은 구도가 되는 시간에는 아직 하늘이 밝습니다.'
            : '현재 관측지에서 가려지는 방향입니다.',
      );
    }
    return MultiNightFramingMatchResult(
      reference: reference,
      site: site,
      equipment: equipment,
      isAvailable: true,
      recommendedAt: DateTime(2026, 8, 4, 20, 14),
      framingMatchAt: DateTime(2026, 8, 4, 20, 14),
      rangeStart: DateTime(2026, 8, 4, 20, 9),
      rangeEnd: DateTime(2026, 8, 4, 20, 19),
      darkStart: DateTime(2026, 8, 4, 20),
      darkEnd: DateTime(2026, 8, 5, 4),
      hourAngleDeg: -20,
      parallacticAngleDeg: 15,
      parallacticAngleDifferenceDeg: 0,
      altitudeDeg: 30,
      azimuthDeg: 180,
    );
  }
}

const _m16 = CatalogObject(
  id: 'M16',
  number: 16,
  catalog: CatalogType.messier,
  name: '독수리성운',
  type: '성운',
  constellation: '뱀자리',
  ra: '18h 18.8m',
  dec: '-13° 47m',
  magnitude: '6.0',
);

const _draco = Equipment(
  id: 'draco',
  name: 'Draco',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

const _seestar = Equipment(
  id: 'seestar',
  name: 'Seestar',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

final _site = ObservationSite(
  id: 'home',
  name: '집',
  latitude: 37.5,
  longitude: 127,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _site2 = ObservationSite(
  id: 'outskirts',
  name: '외곽',
  latitude: 36.5,
  longitude: 127.5,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _reference = MultiNightFramingReference(
  id: 'reference',
  catalogObjectId: 'M16',
  referenceCapturedAt: DateTime(2026, 7, 15, 21, 10),
  siteId: 'home',
  equipmentId: 'draco',
  referenceHourAngleDeg: -20,
  referenceParallacticAngleDeg: 15,
  referenceBranch: MultiNightFramingBranch.rising,
  revision: 1,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeReferenceRepository implements MultiNightFramingReferenceRepository {
  _FakeReferenceRepository([this.values = const []]);

  List<MultiNightFramingReference> values;

  @override
  Future<void> create(MultiNightFramingReference reference) async {
    values = [...values, reference];
  }

  @override
  Future<void> delete(String id) async {
    values = values.where((value) => value.id != id).toList();
  }

  @override
  Future<MultiNightFramingReference?> find({
    required String catalogObjectId,
    required String equipmentId,
  }) async {
    for (final value in values) {
      if (value.catalogObjectId == catalogObjectId &&
          value.equipmentId == equipmentId) {
        return value;
      }
    }
    return null;
  }

  @override
  Future<MultiNightFramingReference?> get(String id) async {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }

  @override
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  }) async => values
      .where(
        (value) =>
            (catalogObjectId == null ||
                value.catalogObjectId == catalogObjectId) &&
            (equipmentId == null || value.equipmentId == equipmentId),
      )
      .toList();

  @override
  Future<String?> latestConflictForCatalog(String catalogObjectId) async =>
      null;

  @override
  Future<void> update(MultiNightFramingReference reference) async {
    values = [
      for (final value in values)
        if (value.id == reference.id) reference else value,
    ];
  }
}

class _FakeEquipmentRepository implements EquipmentRepository {
  const _FakeEquipmentRepository(this.values);
  final List<Equipment> values;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => values;

  @override
  Future<Equipment?> getById(String id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<void> save(Equipment equipment) async {}
}

class _FakeSiteRepository implements ObservationSiteRepository {
  const _FakeSiteRepository(this.values);
  final List<ObservationSite> values;

  @override
  Future<void> addBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> addHorizonPoint(HorizonPoint point) async {}
  @override
  Future<void> create(ObservationSite site) async {}
  @override
  Future<void> createFavorite(ObservationSite site) async {}
  @override
  Future<void> delete(String id, {bool hard = false}) async {}
  @override
  Future<void> deleteBlockedRange(String id) async {}
  @override
  Future<void> deleteHorizonPoint(String id) async {}
  @override
  Future<ObservationSite?> get(
    String id, {
    bool includeDeleted = false,
  }) async => values.where((value) => value.id == id).firstOrNull;
  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async =>
      values;
  @override
  Future<List<BlockedAzimuthRange>> listBlockedRanges(String siteId) async =>
      const [];
  @override
  Future<List<HorizonPoint>> listHorizonPoints(String siteId) async => const [];
  @override
  Future<void> markLastUsed(String id, DateTime usedAt) async {}
  @override
  Future<void> replaceBlockedRanges(
    String siteId,
    List<BlockedAzimuthRange> ranges,
  ) async {}
  @override
  Future<void> replaceHorizonPoints(
    String siteId,
    List<HorizonPoint> points,
  ) async {}
  @override
  Future<void> setFavorite(String id, bool favorite) async {}
  @override
  Future<void> update(ObservationSite site) async {}
  @override
  Future<void> updateBlockedRange(BlockedAzimuthRange range) async {}
  @override
  Future<void> updateHorizonPoint(HorizonPoint point) async {}
}

extension<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}
