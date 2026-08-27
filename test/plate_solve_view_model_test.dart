import 'dart:async';
import 'dart:convert';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/api_test_result.dart';
import 'package:astro_journal/data/datasources/common_file_link_datasource.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/photo_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/photo_object_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/gallery/viewmodel/plate_solve_view_model.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/celestial_object_search_service.dart';
import 'package:astro_journal/services/plate_solve/plate_solve_provider.dart';
import 'package:astro_journal/services/plate_solve_service.dart';
import 'package:astro_journal/services/plate_solve_settings_service.dart';
import 'package:astro_journal/services/tc_backend_external_api_client.dart';
import 'package:astro_journal/services/tc_backend_plate_solve_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GalleryViewModel galleryViewModel;
  late _FakeShootingRecordRepository shootingRecordRepository;
  late _FakePhotoObjectRepository photoObjectRepository;
  late _FakeCatalogRepository catalogRepository;
  late _FakeEquipmentRepository equipmentRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    shootingRecordRepository = _FakeShootingRecordRepository();
    photoObjectRepository = _FakePhotoObjectRepository();
    catalogRepository = _FakeCatalogRepository();
    equipmentRepository = _FakeEquipmentRepository();
    galleryViewModel = GalleryViewModel(
      shootingRecordRepository,
      catalogRepository,
      CatalogSearchService(),
    );
  });

  PlateSolveViewModel buildViewModel({
    required PlateSolveProvider provider,
    PlateSolveService? service,
    CommonFileLinkDataSource? commonFileLinks,
  }) {
    final searchService = CelestialObjectSearchService(
      catalogRepository,
      photoObjectRepository,
    );
    return PlateSolveViewModel(
      service ?? PlateSolveService([provider], PlateSolveSettingsService()),
      PlateSolveSettingsService(),
      galleryViewModel,
      searchService,
      catalogRepository,
      equipmentRepository,
      commonFileLinks: commonFileLinks,
    );
  }

  group('solve Targeted / Blind', () {
    test('celestial_object_id가 Catalog에 있으면 Targeted 힌트로 실행한다', () async {
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 10.68, centerDec: 41.27),
      );
      final viewModel = buildViewModel(provider: provider);

      final record = ShootingRecord(
        id: 'photo-1',
        celestialObjectId: 'M31',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/a.jpg',
      );

      final result = await viewModel.solve(record);

      expect(result.success, isTrue);
      expect(result.solveMode, PlateSolveMode.targeted);
      expect(result.targetObject, 'M31');
      expect(result.inputRa, isNotNull);
      expect(result.inputDec, isNotNull);
      expect(provider.calls, isNotEmpty);
      expect(provider.calls.first.centerRa, isNotNull);
      expect(provider.calls.first.centerDec, isNotNull);
      expect(provider.calls.first.searchRadiusDeg, greaterThan(2));
      // 장비 FOV scale 적용
      expect(provider.calls.first.scaleLower, closeTo(0.36, 0.01));
      expect(shootingRecordRepository.updateCalls, isNotEmpty);
      expect(
        shootingRecordRepository.updateCalls.last.plateSolve?.solveMode,
        PlateSolveMode.targeted,
      );
    });

    test('Catalog에 없으면 Blind Solve를 실행한다', () async {
      catalogRepository.objects.clear();
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 1, centerDec: 1),
      );
      final viewModel = buildViewModel(provider: provider);

      final record = ShootingRecord(
        id: 'photo-2',
        celestialObjectId: 'UNKNOWN',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/b.jpg',
      );

      final result = await viewModel.solve(record);

      expect(result.success, isTrue);
      expect(result.solveMode, PlateSolveMode.blind);
      expect(provider.calls.single.centerRa, isNull);
      expect(provider.calls.single.centerDec, isNull);
    });

    test('Targeted 실패 시 Blind까지 폴백한다', () async {
      var callCount = 0;
      final provider = _RecordingPlateSolveProvider.dynamic((call) {
        callCount++;
        // 앞의 Targeted 시도는 실패, Blind에서 성공
        if (call.centerRa == null) {
          return PlateSolveResult.success(centerRa: 83.8, centerDec: -5.4);
        }
        return PlateSolveResult.failure(errorMessage: 'no match');
      });
      final viewModel = buildViewModel(provider: provider);

      final record = ShootingRecord(
        id: 'photo-3',
        celestialObjectId: 'M42',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/c.jpg',
      );

      final result = await viewModel.solve(record);

      expect(result.success, isTrue);
      expect(result.solveMode, PlateSolveMode.blind);
      expect(result.targetObject, 'M42');
      expect(callCount, 4);
      expect(provider.calls.last.centerRa, isNull);
    });

    test('사진 없으면 실패', () async {
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 1, centerDec: 1),
      );
      final viewModel = buildViewModel(provider: provider);

      final record = ShootingRecord(
        id: 'photo-4',
        celestialObjectId: 'M31',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final result = await viewModel.solve(record);
      expect(result.success, isFalse);
      expect(provider.calls, isEmpty);
    });

    test('등록 전 사진은 direct provider 없이 안전하게 안내한다', () async {
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 1, centerDec: 1),
      );
      final viewModel = buildViewModel(
        provider: provider,
        commonFileLinks: const _FakeCommonFileLinks(null),
      );
      final record = ShootingRecord(
        id: 'pending-photo',
        celestialObjectId: 'M31',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/pending.jpg',
      );

      final result = await viewModel.solve(record);

      expect(result.success, isFalse);
      expect(result.errorMessage, '사진 등록이 완료된 후 Plate Solve를 사용할 수 있습니다.');
      expect(provider.calls, isEmpty);
    });

    test('common_file_id가 있으면 Backend-only solve 결과를 저장한다', () async {
      var backendCalls = 0;
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.failure(errorMessage: 'direct must not run'),
      );
      final service = _backendPlateSolveService(provider, (request) async {
        backendCalls++;
        return http.Response(
          '{"job_id":"job-1","status":"COMPLETED","common_file_id":178,'
          '"provider":"astrometry.net","result":{"ra":10,"dec":20}}',
          200,
        );
      });
      final viewModel = buildViewModel(
        provider: provider,
        service: service,
        commonFileLinks: const _FakeCommonFileLinks(null),
      );

      final result = await viewModel.solve(_registeredRecord());

      expect(result.success, isTrue);
      expect(backendCalls, 1);
      expect(provider.calls, isEmpty);
      expect(
        shootingRecordRepository.updateCalls.last.plateSolve?.success,
        isTrue,
      );
    });

    test('Backend provider unavailable은 credential 용어 없이 안내한다', () async {
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.failure(errorMessage: 'direct must not run'),
      );
      final service = _backendPlateSolveService(
        provider,
        (_) async => http.Response(
          '{"detail":{"code":"API_KEY_NOT_CONFIGURED",'
          '"message":"provider detail"}}',
          503,
        ),
      );
      final viewModel = buildViewModel(
        provider: provider,
        service: service,
        commonFileLinks: const _FakeCommonFileLinks(null),
      );

      final result = await viewModel.solve(_registeredRecord());

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Plate Solve 서비스를 사용할 수 없습니다.');
      expect(result.errorMessage, isNot(contains('API Key')));
      expect(provider.calls, isEmpty);
    });

    test('backend_record_id is never used as common_file_id', () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);
      var backendCalls = 0;
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 1, centerDec: 1),
      );
      final service = _backendPlateSolveService(provider, (request) async {
        backendCalls++;
        return http.Response('{}', 200);
      });
      final viewModel = buildViewModel(
        provider: provider,
        service: service,
        commonFileLinks: const _FakeCommonFileLinks(null),
      );
      final record = ShootingRecord(
        id: 'remote:record-1',
        celestialObjectId: 'M31',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/api/common/gallery/sha-1/preview',
        backendRecordId: 'record-1',
        backendFileId: 'sha-1',
      );

      final result = await viewModel.solve(record);

      expect(result.success, isFalse);
      expect(result.errorMessage, '사진 등록이 완료된 후 Plate Solve를 사용할 수 있습니다.');
      expect(backendCalls, 0);
      expect(provider.calls, isEmpty);
      expect(logs, contains(contains('shooting_record_id=remote:record-1')));
      expect(logs, contains(contains('backend_record_id=record-1')));
      expect(logs, contains(contains('backend_file_id=sha-1')));
      expect(logs, contains(contains('common_file_id=null')));
      expect(logs, contains(contains('common_file_id_source=none')));
    });

    test(
      'identity diagnostic distinguishes ShootingRecord and sync_outbox',
      () async {
        final logs = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = previousDebugPrint);
        final provider = _RecordingPlateSolveProvider(
          PlateSolveResult.success(centerRa: 1, centerDec: 1),
        );

        await buildViewModel(
          provider: provider,
          commonFileLinks: const _FakeCommonFileLinks(null),
        ).solve(_registeredRecord());
        await buildViewModel(
          provider: provider,
          commonFileLinks: const _FakeCommonFileLinks(179),
        ).solve(
          ShootingRecord(
            id: 'local-outbox-record',
            celestialObjectId: 'M31',
            capturedAt: DateTime(2026, 1, 1),
            createdAt: DateTime(2026, 1, 1),
            photoUri: '/registered.jpg',
          ),
        );

        expect(
          logs,
          contains(
            contains('common_file_id=178 common_file_id_source=ShootingRecord'),
          ),
        );
        expect(
          logs,
          contains(
            contains('common_file_id=179 common_file_id_source=sync_outbox'),
          ),
        );
      },
    );

    test('duplicate solve shares one in-flight request', () async {
      final record = ShootingRecord(
        id: 'duplicate-photo',
        celestialObjectId: 'UNKNOWN',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/duplicate.jpg',
      );
      shootingRecordRepository.items[record.id] = record;
      await galleryViewModel.load();
      final provider = _DelayedPlateSolveProvider();
      final viewModel = buildViewModel(provider: provider);

      final first = viewModel.solve(record);
      final second = viewModel.solve(record);
      await provider.started.future;

      expect(provider.calls, 1);
      provider.complete(PlateSolveResult.success(centerRa: 10, centerDec: 20));
      expect((await first).success, isTrue);
      expect((await second).success, isTrue);
      expect(provider.calls, 1);
    });

    test(
      'solve completion merges into the latest record instead of stale input',
      () async {
        final record = ShootingRecord(
          id: 'stale-photo',
          celestialObjectId: 'UNKNOWN',
          capturedAt: DateTime(2026, 1, 1),
          createdAt: DateTime(2026, 1, 1),
          photoUri: '/stale.jpg',
          memo: 'before',
        );
        shootingRecordRepository.items[record.id] = record;
        await galleryViewModel.load();
        final provider = _DelayedPlateSolveProvider();
        final viewModel = buildViewModel(provider: provider);

        final solve = viewModel.solve(record);
        await provider.started.future;
        await galleryViewModel.updateRecord(record.copyWith(memo: 'edited'));
        provider.complete(
          PlateSolveResult.success(centerRa: 10, centerDec: 20),
        );
        await solve;

        final saved = shootingRecordRepository.items[record.id]!;
        expect(saved.memo, 'edited');
        expect(saved.plateSolve?.success, isTrue);
      },
    );

    test(
      'completion after record removal does not restore the deleted record',
      () async {
        final record = ShootingRecord(
          id: 'deleted-photo',
          celestialObjectId: 'UNKNOWN',
          capturedAt: DateTime(2026, 1, 1),
          createdAt: DateTime(2026, 1, 1),
          photoUri: '/deleted.jpg',
        );
        shootingRecordRepository.items[record.id] = record;
        await galleryViewModel.load();
        final provider = _DelayedPlateSolveProvider();
        final viewModel = buildViewModel(provider: provider);

        final solve = viewModel.solve(record);
        await provider.started.future;
        shootingRecordRepository.items.remove(record.id);
        await galleryViewModel.load(silent: true);
        provider.complete(
          PlateSolveResult.success(centerRa: 10, centerDec: 20),
        );
        await solve;

        expect(shootingRecordRepository.items, isNot(contains(record.id)));
        expect(
          shootingRecordRepository.updateCalls.where(
            (item) => item.id == record.id && item.plateSolve?.success == true,
          ),
          isEmpty,
        );
      },
    );

    test('failed solve leaves the action retryable', () async {
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.failure(errorMessage: 'not solved'),
      );
      final viewModel = buildViewModel(provider: provider);
      final record = ShootingRecord(
        id: 'retry-photo',
        celestialObjectId: 'UNKNOWN',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/retry.jpg',
      );

      expect((await viewModel.solve(record)).success, isFalse);
      expect(viewModel.stateFor(record.id).isRunning, isFalse);
      expect((await viewModel.solve(record)).success, isFalse);
      expect(provider.calls, hasLength(2));
    });

    testWidgets('Plate Solve action shows progress and completed result', (
      tester,
    ) async {
      final record = ShootingRecord(
        id: 'widget-photo',
        celestialObjectId: 'UNKNOWN',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/widget.jpg',
      );
      shootingRecordRepository.items[record.id] = record;
      await galleryViewModel.load();
      final provider = _DelayedPlateSolveProvider();
      final viewModel = buildViewModel(provider: provider);

      await tester.pumpWidget(
        ChangeNotifierProvider<PlateSolveViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            home: Scaffold(
              body: GalleryPlateSolveSection(
                record: record,
                onRun: () => unawaited(viewModel.solve(record)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plate Solve 실행'));
      await provider.started.future;
      await tester.pump();

      expect(find.byKey(const Key('plate-solve-processing')), findsOneWidget);
      expect(find.text('Blind Solve...'), findsOneWidget);
      expect(provider.calls, 1);

      provider.complete(PlateSolveResult.success(centerRa: 10, centerDec: 20));
      await tester.pumpAndSettle();
      expect(find.text('중심 RA'), findsOneWidget);
      expect(find.text('Plate Solve 다시 실행'), findsOneWidget);
    });

    testWidgets('pre-upload Plate Solve failure is visible and retryable', (
      tester,
    ) async {
      final record = ShootingRecord(
        id: 'not-uploaded-widget-photo',
        celestialObjectId: 'M31',
        capturedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        photoUri: '/pending.jpg',
      );
      final provider = _RecordingPlateSolveProvider(
        PlateSolveResult.success(centerRa: 1, centerDec: 1),
      );
      final viewModel = buildViewModel(
        provider: provider,
        commonFileLinks: const _FakeCommonFileLinks(null),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<PlateSolveViewModel>.value(
          value: viewModel,
          child: MaterialApp(
            home: Scaffold(
              body: GalleryPlateSolveSection(
                record: record,
                onRun: () => unawaited(viewModel.solve(record)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Plate Solve 실행'));
      await tester.pump();

      expect(
        find.text('사진 등록이 완료된 후 Plate Solve를 사용할 수 있습니다.'),
        findsOneWidget,
      );
      expect(find.text('Plate Solve 다시 실행'), findsOneWidget);
      expect(provider.calls, isEmpty);
    });
  });

  test(
    'Backend contract posts common_file_id and polls job_id to completion',
    () async {
      final requests = <http.Request>[];
      var pollCount = 0;
      final client = TcBackendExternalApiClient(
        settingsService: TcBackendSettingsService(
          useBuildConfiguration: true,
          buildBaseUrl: 'https://backend.test',
        ),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            return http.Response(
              '{"job_id":"job-42","status":"WAITING",'
              '"common_file_id":178}',
              200,
            );
          }
          pollCount++;
          if (pollCount == 1) {
            return http.Response(
              '{"job_id":"job-42","status":"PROCESSING",'
              '"common_file_id":178}',
              200,
            );
          }
          return http.Response(
            '{"job_id":"job-42","status":"COMPLETED",'
            '"common_file_id":178,"provider":"astrometry.net",'
            '"result":{"ra":10,"dec":20}}',
            200,
          );
        }),
      );
      final progress = <String>[];
      final service = TcBackendPlateSolveService(
        client: client,
        pollInterval: Duration.zero,
        delay: (_) async {},
      );

      final result = await service.solve(
        commonFileId: 178,
        onProgress: (event) => progress.add(event.message),
      );

      expect(result.success, isTrue);
      expect(requests.map((request) => request.method), ['POST', 'GET', 'GET']);
      expect(requests.first.url.path, '/api/astro/plate-solve');
      expect(jsonDecode(requests.first.body), {'common_file_id': 178});
      expect(
        requests.skip(1).map((request) => request.url.path),
        everyElement('/api/astro/plate-solve/job-42'),
      );
      expect(progress, contains('Plate Solve 대기 중…'));
      expect(progress, contains('Plate Solving…'));
    },
  );
}

PlateSolveService _backendPlateSolveService(
  PlateSolveProvider provider,
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = TcBackendExternalApiClient(
    settingsService: TcBackendSettingsService(
      useBuildConfiguration: true,
      buildBaseUrl: 'https://backend.test',
    ),
    client: MockClient(handler),
  );
  return PlateSolveService(
    [provider],
    PlateSolveSettingsService(),
    backendService: TcBackendPlateSolveService(client: client),
  );
}

ShootingRecord _registeredRecord() => ShootingRecord(
  id: 'registered-photo',
  celestialObjectId: 'M31',
  capturedAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  photoUri: '/registered.jpg',
  commonFileId: 178,
);

class _FakeCommonFileLinks implements CommonFileLinkDataSource {
  const _FakeCommonFileLinks(this.value);

  final int? value;

  @override
  Future<int?> getCommonFileId(String localRecordId) async => value;
}

class _SolveCall {
  const _SolveCall({
    this.centerRa,
    this.centerDec,
    this.searchRadiusDeg,
    this.scaleLower,
    this.scaleUpper,
  });

  final double? centerRa;
  final double? centerDec;
  final double? searchRadiusDeg;
  final double? scaleLower;
  final double? scaleUpper;
}

class _RecordingPlateSolveProvider implements PlateSolveProvider {
  _RecordingPlateSolveProvider(this._fixed) : _dynamic = null;

  _RecordingPlateSolveProvider.dynamic(this._dynamic) : _fixed = null;

  final PlateSolveResult? _fixed;
  final PlateSolveResult Function(_SolveCall call)? _dynamic;
  final List<_SolveCall> calls = [];

  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake Provider';

  @override
  Future<bool> get isConfigured async => true;

  @override
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    final call = _SolveCall(
      centerRa: centerRa,
      centerDec: centerDec,
      searchRadiusDeg: searchRadiusDeg,
      scaleLower: scaleLower,
      scaleUpper: scaleUpper,
    );
    calls.add(call);
    onProgress?.call(
      const PlateSolveProgress(PlateSolveStage.uploading, 'Plate Solving...'),
    );
    return _dynamic?.call(call) ?? _fixed!;
  }

  @override
  Future<ApiTestResult> testConnection() async =>
      ApiTestResult.failure(message: 'not used');
}

class _DelayedPlateSolveProvider implements PlateSolveProvider {
  final Completer<void> started = Completer<void>();
  final Completer<PlateSolveResult> _result = Completer<PlateSolveResult>();
  int calls = 0;

  void complete(PlateSolveResult result) => _result.complete(result);

  @override
  String get id => 'delayed';

  @override
  String get displayName => 'Delayed Provider';

  @override
  Future<bool> get isConfigured async => true;

  @override
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  @override
  Future<ApiTestResult> testConnection() async =>
      ApiTestResult.failure(message: 'not used');
}

class _FakeCatalogRepository implements CatalogRepository {
  final Map<String, CatalogObject> objects = {
    'M31': CatalogObject(
      id: 'M31',
      number: 31,
      catalog: CatalogType.messier,
      name: 'M31',
      type: '은하',
      constellation: 'And',
      ra: '0h42.7m',
      dec: '+41d16m',
      magnitude: '3.4',
      angularSize: "190' × 60'",
    ),
    'M42': CatalogObject(
      id: 'M42',
      number: 42,
      catalog: CatalogType.messier,
      name: 'M42',
      type: '성운',
      constellation: 'Ori',
      ra: '5h35.4m',
      dec: '-5d27m',
      magnitude: '4.0',
      angularSize: "85' × 60'",
    ),
  };

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async =>
      objects.values.toList();

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];

  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async => const [];

  @override
  Future<CatalogObject?> getById(String id) async => objects[id];

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async =>
      objects.values.where((o) => o.catalog == type).toList();

  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      const [];

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}

  @override
  Future<void> insert(CatalogObject object) async {}

  @override
  Future<void> delete(String id) async {}
}

class _FakeEquipmentRepository implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [
    Equipment(
      id: 'cam-1',
      name: 'Seestar S50',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      fovWidthDegrees: 1.28,
      fovHeightDegrees: 0.72,
    ),
  ];

  @override
  Future<Equipment?> getById(String id) async => null;

  @override
  Future<void> save(Equipment equipment) async {}

  @override
  Future<void> delete(String id) async {}
}

class _FakePhotoObjectRepository implements PhotoObjectRepository {
  final List<(String, List<PhotoObject>)> replaceForPhotoCalls = [];

  @override
  Future<List<PhotoObject>> getByPhotoId(String photoId) async => const [];

  @override
  Future<void> replaceForPhoto(
    String photoId,
    List<PhotoObject> objects,
  ) async {
    replaceForPhotoCalls.add((photoId, objects));
  }

  @override
  Future<void> deleteByPhotoId(String photoId) async {}
}

class _FakeShootingRecordRepository implements ShootingRecordRepository {
  final List<ShootingRecord> updateCalls = [];
  final Map<String, ShootingRecord> items = {};

  @override
  Future<void> clearRepresentativeForObject(String celestialObjectId) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<ShootingRecord?> findByObjectAndCapturedAt(
    String celestialObjectId,
    DateTime capturedAt, {
    Duration tolerance = const Duration(minutes: 1),
  }) async => null;

  @override
  Future<ShootingRecord?> findByOriginalFilename(
    String originalFilename,
  ) async => null;

  @override
  Future<List<ShootingRecord>> getAll() async => items.values.toList();

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(
    String celestialObjectId,
  ) async => const [];

  @override
  Future<ShootingRecord?> getById(String id) async => items[id];

  @override
  Future<void> save(ShootingRecord record) async {}

  @override
  Future<void> setRepresentative(String recordId) async {}

  @override
  Future<void> update(ShootingRecord record) async {
    updateCalls.add(record);
    items[record.id] = record;
  }
}
