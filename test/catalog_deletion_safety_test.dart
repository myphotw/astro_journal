import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/policies/catalog_deletion_policy.dart';
import 'package:astro_journal/data/datasources/catalog_local_datasource.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/catalog_repository_impl.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/catalog/view/catalog_detail_screen.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_detail_view_model.dart';
import 'package:astro_journal/services/base_exposure_settings_service.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/metadata_service.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/photo_registration_service.dart';
import 'package:astro_journal/services/catalog_fts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

const _customId = '550e8400-e29b-41d4-a716-446655440000';

const _messier = CatalogObject(
  id: 'M42',
  number: 42,
  catalog: CatalogType.messier,
  name: '오리온 성운',
  type: '발광성운',
  constellation: '오리온자리',
  ra: '05h 35m',
  dec: '-05 23',
  magnitude: '4.0',
);

const _ngc = CatalogObject(
  id: 'NGC7000',
  number: 7000,
  catalog: CatalogType.ngc,
  name: '북아메리카 성운',
  type: '발광성운',
  constellation: '백조자리',
  ra: '20h 59m',
  dec: '+44 31',
  magnitude: '4.0',
);

const _seedStar = CatalogObject(
  id: 'STAR_SIRIUS',
  number: 1,
  catalog: CatalogType.star,
  name: '시리우스',
  type: '별',
  constellation: '큰개자리',
  ra: '06h 45m',
  dec: '-16 43',
  magnitude: '-1.46',
  dataSource: 'Manual',
);

const _custom = CatalogObject(
  id: _customId,
  number: 1,
  catalog: CatalogType.ngc,
  name: '사용자 성운',
  type: '성운',
  constellation: '테스트자리',
  ra: '',
  dec: '',
  magnitude: '-',
  tags: [CatalogDeletionPolicy.userCreatedTag],
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Catalog deletion identity policy', () {
    test('Messier, NGC, and another seed type cannot be deleted', () {
      expect(_messier.isBuiltIn, isTrue);
      expect(_messier.canDelete, isFalse);
      expect(_ngc.isBuiltIn, isTrue);
      expect(_ngc.canDelete, isFalse);
      expect(_seedStar.isBuiltIn, isTrue);
      expect(_seedStar.canDelete, isFalse);
    });

    test('legacy UUID and tagged user target can be deleted', () {
      expect(_custom.isCustom, isTrue);
      expect(_custom.canDelete, isTrue);
      expect(CatalogDeletionPolicy.canDelete(id: _customId), isTrue);
    });
  });

  group('Repository deletion safety', () {
    test(
      'repository and data source both reject a built-in seed row',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        await CatalogFtsService.ensureSchema(db);
        await db.insert(
          DatabaseConstants.tableCelestialObjects,
          _messier.toMap(),
        );
        await db.insert(
          DatabaseConstants.tableShootingRecords,
          _record(catalogId: _messier.id).toMap(),
        );

        final dataSource = CatalogLocalDataSource(database: db);
        final repository = CatalogRepositoryImpl(dataSource: dataSource);

        await expectLater(repository.delete(_messier.id), throwsStateError);
        await expectLater(dataSource.delete(_messier.id), throwsStateError);

        expect(await repository.getById(_messier.id), isNotNull);
        expect(
          await db.query(DatabaseConstants.tableShootingRecords),
          hasLength(1),
        );
      },
    );

    test(
      'custom delete hides only target and preserves related local data',
      () async {
        final db = await openTestDatabase();
        addTearDown(db.close);
        await CatalogFtsService.ensureSchema(db);
        await db.execute('''
        CREATE TABLE ${DatabaseConstants.tablePhotos} (
          ${DatabaseConstants.colId} TEXT PRIMARY KEY,
          ${DatabaseConstants.colLocalPath} TEXT NOT NULL
        )
      ''');
        await db.execute('''
        CREATE TABLE ${DatabaseConstants.tableSyncOutbox} (
          ${DatabaseConstants.colId} TEXT PRIMARY KEY,
          local_record_id TEXT,
          payload_json TEXT
        )
      ''');
        await db.insert(
          DatabaseConstants.tableCelestialObjects,
          _custom.toMap(),
        );
        await db.insert(
          DatabaseConstants.tableShootingRecords,
          _record(catalogId: _custom.id).toMap(),
        );
        await db.insert(DatabaseConstants.tablePhotos, {
          DatabaseConstants.colId: 'photo-1',
          DatabaseConstants.colLocalPath: 'photo.jpg',
        });
      await db.insert(DatabaseConstants.tableSyncOutbox, {
          DatabaseConstants.colId: 'outbox-1',
          'local_record_id': 'record-1',
        'payload_json': '{"canonical_target_id":"$_customId"}',
      });
      await CatalogFtsService.rebuild(db);

      final repository = CatalogRepositoryImpl(
        dataSource: CatalogLocalDataSource(database: db),
      );
      expect(await repository.search('사용자 성운'), hasLength(1));
      await repository.delete(_custom.id);

      expect(await repository.getAll(), isEmpty);
      expect(await repository.search('사용자 성운'), isEmpty);
      final retainedTarget = await repository.getById(_custom.id);
      expect(retainedTarget, isNotNull);
      expect(retainedTarget!.isDeleted, isTrue);
      expect(retainedTarget.canDelete, isFalse);
        expect(retainedTarget.name, _custom.name);
        expect(
          await db.query(DatabaseConstants.tableShootingRecords),
          hasLength(1),
        );
        expect(await db.query(DatabaseConstants.tablePhotos), hasLength(1));
        expect(await db.query(DatabaseConstants.tableSyncOutbox), hasLength(1));
      },
    );
  });

  group('Catalog Detail layered safeguards', () {
    test(
      'ViewModel rejects built-in deletion before repository calls',
      () async {
        final catalog = _MemoryCatalog([_messier]);
        final records = _MemoryRecords([_record(catalogId: _messier.id)]);
        final viewModel = _viewModel(_messier, catalog, records);

        await viewModel.deleteObject();

        expect(catalog.deleteCalls, isEmpty);
        expect(records.deleteCalls, isEmpty);
        expect(records.records, hasLength(1));
        expect(viewModel.errorMessage, contains('삭제할 수 없습니다'));
      },
    );

    testWidgets('delete button is hidden for built-in and shown for custom', (
      tester,
    ) async {
      final builtInVm = _viewModel(
        _messier,
        _MemoryCatalog([_messier]),
        _MemoryRecords(),
      );
      await _pumpDetail(tester, builtInVm);
      expect(find.byKey(const Key('catalog-delete-button')), findsNothing);

      final customVm = _viewModel(
        _custom,
        _MemoryCatalog([_custom]),
        _MemoryRecords([_record(catalogId: _custom.id)]),
      );
      await _pumpDetail(tester, customVm);
      expect(find.byKey(const Key('catalog-delete-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalog-delete-button')));
      await tester.pumpAndSettle();
      expect(find.text('사용자 대상 삭제'), findsOneWidget);
      expect(find.textContaining('촬영 기록과 사진은 삭제되지 않습니다'), findsOneWidget);
    });

    test('custom ViewModel deletes no shooting records', () async {
      final catalog = _MemoryCatalog([_custom]);
      final records = _MemoryRecords([_record(catalogId: _custom.id)]);
      final viewModel = _viewModel(_custom, catalog, records);

      await viewModel.deleteObject();

      expect(catalog.deleteCalls, [_custom.id]);
      expect(records.deleteCalls, isEmpty);
      expect(records.records, hasLength(1));
      expect(viewModel.objects, isEmpty);
    });
  });
}

ShootingRecord _record({required String catalogId}) => ShootingRecord(
  id: 'record-1',
  celestialObjectId: catalogId,
  capturedAt: DateTime.utc(2026, 8, 24),
  photoUri: 'photo.jpg',
  createdAt: DateTime.utc(2026, 8, 24),
);

CatalogDetailViewModel _viewModel(
  CatalogObject object,
  CatalogRepository catalog,
  ShootingRecordRepository records,
) {
  return CatalogDetailViewModel(
    object,
    records,
    catalog,
    _FakeRegistrationService(),
    const MetadataService(),
    _MemoryEquipment(),
    const EquipmentRecommendationService(),
    BaseExposureSettingsService(),
    const ObjectImagingProfileProvider(),
    const ExposurePolicy(),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  CatalogDetailViewModel viewModel,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider.value(
        value: viewModel,
        child: const CatalogDetailScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemoryCatalog implements CatalogRepository {
  _MemoryCatalog(Iterable<CatalogObject> objects)
    : objects = {for (final object in objects) object.id: object};

  final Map<String, CatalogObject> objects;
  final List<String> deleteCalls = [];

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    objects.remove(id);
  }

  @override
  Future<CatalogObject?> getById(String id) async => objects[id];

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async =>
      objects.values.toList();

  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRecords implements ShootingRecordRepository {
  _MemoryRecords([Iterable<ShootingRecord> initial = const []])
    : records = List.of(initial);

  final List<ShootingRecord> records;
  final List<String> deleteCalls = [];

  @override
  Future<List<ShootingRecord>> getAll() async => List.of(records);

  @override
  Future<List<ShootingRecord>> getByCelestialObjectId(String id) async =>
      records.where((record) => record.celestialObjectId == id).toList();

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    records.removeWhere((record) => record.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryEquipment implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRegistrationService implements PhotoRegistrationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
