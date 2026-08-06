import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/datasources/catalog_local_datasource.dart';
import 'package:astro_journal/data/datasources/shooting_record_local_datasource.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ShootingRecordLocalDataSource large data', () {
    late ShootingRecordLocalDataSource shootingDataSource;
    late CatalogLocalDataSource catalogDataSource;

    setUp(() async {
      final db = await openTestDatabase();
      shootingDataSource = ShootingRecordLocalDataSource(database: db);
      catalogDataSource = CatalogLocalDataSource(database: db);

      const objectCount = 200;
      for (var index = 0; index < objectCount; index++) {
        await catalogDataSource.insert(
          CatalogObject(
            id: 'M$index',
            number: index,
            catalog: CatalogType.messier,
            name: 'Object $index',
            type: '성운',
            constellation: 'Test',
            ra: '-',
            dec: '-',
            magnitude: '-',
            aliases: ['alias$index'],
          ),
        );
      }

      const recordCount = 10000;
      final batchBase = DateTime(2020, 1, 1);
      for (var index = 0; index < recordCount; index++) {
        final capturedAt = batchBase.add(Duration(hours: index));
        await shootingDataSource.insert(
          ShootingRecord(
            id: 'record_$index',
            celestialObjectId: 'M${index % objectCount}',
            capturedAt: capturedAt,
            photoUri: '/photos/$index.jpg',
            originalFilename: 'photo_$index.jpg',
            createdAt: capturedAt,
            isFavorite: index.isEven,
          ),
        );
      }
    });

    test('getAll completes within 3 seconds for 10,000 records', () async {
      final stopwatch = Stopwatch()..start();
      final records = await shootingDataSource.getAll();
      stopwatch.stop();

      expect(records.length, 10000);
      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      expect(records.first.capturedAt.isAfter(records.last.capturedAt), isTrue);
    });

    test('getByCelestialObjectId uses index and completes quickly', () async {
      final stopwatch = Stopwatch()..start();
      final records = await shootingDataSource.getByCelestialObjectId('M42');
      stopwatch.stop();

      expect(records, isNotEmpty);
      expect(records.every((record) => record.celestialObjectId == 'M42'), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('findByOriginalFilename completes quickly', () async {
      final stopwatch = Stopwatch()..start();
      final record = await shootingDataSource.findByOriginalFilename('photo_9999.jpg');
      stopwatch.stop();

      expect(record, isNotNull);
      expect(record!.id, 'record_9999');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
