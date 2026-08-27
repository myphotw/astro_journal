import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/datasources/shooting_record_local_datasource.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository_impl.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_detail_view_model.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/metadata_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

void main() {
  final createdAt = DateTime(2026, 8, 27);
  late ShootingRecord original;
  late _RecordRepository records;
  late GalleryViewModel viewModel;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    original = ShootingRecord(
      id: 'record-1',
      celestialObjectId: 'M31',
      capturedAt: createdAt,
      createdAt: createdAt,
      photoUri: '/managed/photo.jpg',
      memo: 'preserve me',
      location: 'Old site',
      exif: ExifInfo.placeholder(filename: 'photo.jpg').copyWith(
        equipment: 'Old equipment',
        exposure: '30분',
        locationName: 'Old site',
        lat: 37,
        lng: 127,
      ),
      plateSolve: PlateSolveResult.success(centerRa: 10, centerDec: 20),
    );
    records = _RecordRepository([original]);
    viewModel = GalleryViewModel(
      records,
      _CatalogRepository(),
      CatalogSearchService(),
    );
    await viewModel.load();
  });

  test(
    'integration equipment and site survive save, edit, and reload',
    () async {
      final edited = original.copyWith(
        location: 'New site',
        exif: original.exif!.copyWith(
          equipment: 'Seestar S30 Pro',
          exposure: '1시간30분',
          locationName: 'New site',
          address: 'Seoul',
          lat: 37.55,
          lng: 126.98,
        ),
      );

      expect(await viewModel.updateRecord(edited), isTrue);
      final reloaded = await viewModel.loadDetailRecord(edited);

      expect(reloaded.exif?.exposure, '1시간30분');
      expect(MetadataFormat.secondsFromDisplay(reloaded.exif!.exposure), 5400);
      expect(reloaded.exif?.equipment, 'Seestar S30 Pro');
      expect(reloaded.location, 'New site');
      expect(reloaded.exif?.locationName, 'New site');
      expect(reloaded.exif?.address, 'Seoul');
      expect(reloaded.exif?.lat, 37.55);
      expect(reloaded.exif?.lng, 126.98);
      expect(reloaded.photoUri, original.photoUri);
      expect(reloaded.plateSolve?.success, isTrue);

      final changedAgain = reloaded.copyWith(
        exif: reloaded.exif!.copyWith(exposure: '2시간'),
      );
      expect(await viewModel.updateRecord(changedAgain), isTrue);
      expect(
        (await viewModel.loadDetailRecord(changedAgain)).exif?.exposure,
        '2시간',
      );
    },
  );

  test(
    'failed persistence keeps the previously loaded canonical record',
    () async {
      records.failUpdates = true;
      final edited = original.copyWith(
        exif: original.exif!.copyWith(exposure: '2시간'),
      );

      expect(await viewModel.updateRecord(edited), isFalse);
      expect(viewModel.recordForId(original.id)?.exif?.exposure, '30분');
      expect(records.items[original.id]?.exif?.exposure, '30분');
    },
  );

  test('SQLite metadata survives ViewModel and Repository recreation', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final firstRepository = ShootingRecordRepositoryImpl(
      dataSource: ShootingRecordLocalDataSource(database: database),
    );
    await firstRepository.save(original);
    final firstViewModel = GalleryViewModel(
      firstRepository,
      _CatalogRepository(),
      CatalogSearchService(),
    );
    await firstViewModel.load();
    final stored = firstViewModel.recordForId(original.id)!;

    expect(
      await firstViewModel.updateRecord(
        stored.copyWith(
          location: '새 관측지',
          exif: stored.exif!.copyWith(
            exposure: '1시간',
            equipment: 'Seestar S30 Pro',
            locationName: '새 관측지',
            lat: 37.5,
            lng: 127.0,
          ),
        ),
      ),
      isTrue,
    );
    firstViewModel.dispose();

    final recreatedRepository = ShootingRecordRepositoryImpl(
      dataSource: ShootingRecordLocalDataSource(database: database),
    );
    final recreatedViewModel = GalleryViewModel(
      recreatedRepository,
      _CatalogRepository(),
      CatalogSearchService(),
    );
    await recreatedViewModel.load();
    final restored = recreatedViewModel.recordForId(original.id)!;

    expect(restored.exif?.exposure, '1시간');
    expect(restored.exif?.equipment, 'Seestar S30 Pro');
    expect(restored.location, '새 관측지');
    expect(restored.exif?.locationName, '새 관측지');
    expect(restored.exif?.lat, 37.5);
    expect(restored.exif?.lng, 127.0);
  });

  testWidgets('editable observation rows remain visible when values are empty', (
    tester,
  ) async {
    final empty = ShootingRecord(
      id: 'empty-record',
      celestialObjectId: 'M31',
      capturedAt: createdAt,
      createdAt: createdAt,
    );
    final detail = GalleryDetailViewModel(records: [empty], initialIndex: 0);
    final gallery = GalleryViewModel(
      _RecordRepository([empty]),
      _CatalogRepository(),
      CatalogSearchService(),
    );
    await gallery.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GalleryViewModel>.value(value: gallery),
          ChangeNotifierProvider<GalleryDetailViewModel>.value(value: detail),
        ],
        child: const MaterialApp(home: GalleryDetailScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('상세정보'));
    await tester.pumpAndSettle();

    expect(find.text('촬영 대상'), findsOneWidget);
    expect(find.text('촬영일시'), findsOneWidget);
    expect(find.text('촬영 장비'), findsOneWidget);
    expect(find.text('적산시간'), findsOneWidget);
    expect(find.text('메모'), findsOneWidget);
    expect(find.text('미입력'), findsNWidgets(2));

    await tester.scrollUntilVisible(
      find.byKey(const Key('gallery-detail-location')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('촬영 위치'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('gallery-detail-location')),
        matching: find.text('미입력'),
      ),
      findsOneWidget,
    );
  });
}

class _RecordRepository implements ShootingRecordRepository {
  _RecordRepository(List<ShootingRecord> records)
    : items = {for (final record in records) record.id: record};

  final Map<String, ShootingRecord> items;
  bool failUpdates = false;

  @override
  Future<List<ShootingRecord>> getAll() async => items.values.toList();

  @override
  Future<ShootingRecord?> getById(String id) async => items[id];

  @override
  Future<void> update(ShootingRecord record) async {
    if (failUpdates) throw StateError('write failed');
    items[record.id] = record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogRepository implements CatalogRepository {
  static const object = CatalogObject(
    id: 'M31',
    number: 31,
    catalog: CatalogType.messier,
    name: 'Andromeda',
    type: 'Galaxy',
    constellation: 'Andromeda',
    ra: '-',
    dec: '-',
    magnitude: '3.4',
  );

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => const [
    object,
  ];

  @override
  Future<CatalogObject?> getById(String id) async =>
      id == object.id ? object : null;

  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
