import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/observation_site_local_datasource.dart';
import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ObservationSiteRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.migrateForTest(db, 31, 32);
    repository = ObservationSiteRepositoryImpl(
      dataSource: ObservationSiteLocalDataSource(database: db),
    );
  });

  tearDown(() => db.close());

  ObservationSite site({String name = 'Seoul'}) {
    final now = DateTime(2026, 8, 18);
    return ObservationSite(
      id: 'site-1',
      name: name,
      address: 'Seoul',
      latitude: 37.5,
      longitude: 127.0,
      bortle: 8,
      trackingMode: TrackingMode.altAz,
      defaultMinAltitude: 20,
      createdAt: now,
      updatedAt: now,
      horizonPoints: const [
        HorizonPoint(
          id: 'point-1',
          observationSiteId: 'site-1',
          azimuth: 120,
          minAltitude: 25,
          maxAltitude: 65,
        ),
      ],
      blockedAzimuthRanges: const [
        BlockedAzimuthRange(
          id: 'range-1',
          observationSiteId: 'site-1',
          startAzimuth: 350,
          endAzimuth: 20,
          reason: 'building',
        ),
      ],
    );
  }

  test('create and read aggregate', () async {
    await repository.create(site());
    final restored = await repository.get('site-1');
    expect(restored?.name, 'Seoul');
    expect(restored?.horizonPoints, hasLength(1));
    expect(restored?.blockedAzimuthRanges.single.contains(355), isTrue);
    expect(restored?.blockedAzimuthRanges.single.contains(10), isTrue);
    expect(restored?.blockedAzimuthRanges.single.contains(180), isFalse);
  });

  test('update, favorite and last-used fields', () async {
    await repository.create(site());
    await repository.update(
      site(name: 'Updated').copyWith(trackingMode: TrackingMode.eq),
    );
    await repository.setFavorite('site-1', false);
    final usedAt = DateTime(2026, 8, 18, 23);
    await repository.markLastUsed('site-1', usedAt);
    final restored = await repository.get('site-1');
    expect(restored?.name, 'Updated');
    expect(restored?.trackingMode, TrackingMode.eq);
    expect(restored?.isFavorite, isFalse);
    expect(restored?.lastUsedAt, usedAt);
  });

  test(
    'horizon and blocked ranges support add update delete replace',
    () async {
      await repository.create(site());
      const point2 = HorizonPoint(
        id: 'point-2',
        observationSiteId: 'site-1',
        azimuth: 150,
        minAltitude: 20,
      );
      await repository.addHorizonPoint(point2);
      await repository.updateHorizonPoint(point2.copyWith(minAltitude: 30));
      expect(
        (await repository.listHorizonPoints('site-1')).last.minAltitude,
        30,
      );
      await repository.deleteHorizonPoint('point-2');
      await repository.replaceHorizonPoints('site-1', const [point2]);
      expect(await repository.listHorizonPoints('site-1'), hasLength(1));

      const range2 = BlockedAzimuthRange(
        id: 'range-2',
        observationSiteId: 'site-1',
        startAzimuth: 100,
        endAzimuth: 110,
      );
      await repository.addBlockedRange(range2);
      await repository.updateBlockedRange(
        const BlockedAzimuthRange(
          id: 'range-2',
          observationSiteId: 'site-1',
          startAzimuth: 105,
          endAzimuth: 115,
        ),
      );
      expect(
        (await repository.listBlockedRanges('site-1')).last.startAzimuth,
        350,
      );
      await repository.deleteBlockedRange('range-2');
      await repository.replaceBlockedRanges('site-1', const [range2]);
      expect(await repository.listBlockedRanges('site-1'), hasLength(1));
    },
  );

  test('soft delete hides site and hard delete removes aggregate', () async {
    await repository.create(site());
    await repository.delete('site-1');
    expect(await repository.get('site-1'), isNull);
    expect(await repository.get('site-1', includeDeleted: true), isNotNull);
    await repository.delete('site-1', hard: true);
    expect(await repository.get('site-1', includeDeleted: true), isNull);
    expect(await repository.listHorizonPoints('site-1'), isEmpty);
  });
}
