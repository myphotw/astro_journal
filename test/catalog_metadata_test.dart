import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database migration v20 columns', () {
    test('celestial_objects includes metadata extension columns', () async {
      final db = await openTestDatabase();
      final info = await db.rawQuery('PRAGMA table_info(celestial_objects)');
      final names = info.map((row) => row['name'] as String).toSet();

      expect(names, contains(DatabaseConstants.colSearchKeywords));
      expect(names, contains(DatabaseConstants.colMajorAxis));
      expect(names, contains(DatabaseConstants.colMinorAxis));
      expect(names, contains(DatabaseConstants.colPositionAngle));
      expect(names, contains(DatabaseConstants.colDataSource));
      expect(names, contains(DatabaseConstants.colIsFeatured));
      expect(names, contains(DatabaseConstants.colDisplayPriority));
      await db.close();
    });

    test('CatalogObject round-trips new metadata fields', () async {
      final db = await openTestDatabase();
      final object = CatalogObject(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: '오리온 성운',
        type: '발광성운',
        constellation: '오리온자리',
        ra: '05h 35m',
        dec: "-05°23'",
        magnitude: '4.0',
        searchKeywords: 'M42|Orion Nebula|오리온',
        majorAxis: 85.0,
        minorAxis: 60.0,
        positionAngle: 45.0,
        dataSource: 'Seestar',
      );

      await db.insert(
        DatabaseConstants.tableCelestialObjects,
        object.toMap(),
      );

      final rows = await db.query(
        DatabaseConstants.tableCelestialObjects,
        where: '${DatabaseConstants.colId} = ?',
        whereArgs: ['M42'],
      );
      final loaded = CatalogObject.fromMap(rows.single);

      expect(loaded.searchKeywords, 'M42|Orion Nebula|오리온');
      expect(loaded.majorAxis, 85.0);
      expect(loaded.minorAxis, 60.0);
      expect(loaded.positionAngle, 45.0);
      expect(loaded.dataSource, 'Seestar');
      await db.close();
    });
  });

  group('CatalogSearchService search_keywords', () {
    test('search matches pipe-delimited search_keywords', () {
      final service = CatalogSearchService();
      final objects = [
        CatalogObject(
          id: 'M31',
          number: 31,
          catalog: CatalogType.messier,
          name: '안드로메다 은하',
          type: '은하',
          constellation: '안드로메다자리',
          ra: '00h 42m',
          dec: "+41°16'",
          magnitude: '3.4',
          searchKeywords: 'M31|NGC 224|Andromeda Galaxy|안드로메다',
        ),
      ];

      final byKorean = service.search('안드로메다', objects);
      expect(byKorean, isNotEmpty);
      expect(byKorean.first.id, 'M31');

      final byCatalog = service.search('NGC 224', objects);
      expect(byCatalog, isNotEmpty);
      expect(byCatalog.first.id, 'M31');
    });
  });
}
