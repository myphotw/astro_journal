import 'dart:convert';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_featured_ranking_service.dart';
import 'package:astro_journal/services/catalog_fts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_database_helper.dart';

CatalogObject _obj({
  required String id,
  required int number,
  required CatalogType catalog,
  required String name,
  String? commonName,
  String objectType = '발광성운',
  String mag = '-',
  String? angularSize,
  String? description,
  List<String> aliases = const [],
  bool seestarSupported = false,
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalog,
    name: name,
    type: objectType,
    objectType: objectType,
    commonName: commonName,
    constellation: '테스트자리',
    ra: '-',
    dec: '-',
    magnitude: mag,
    angularSize: angularSize,
    description: description,
    aliases: aliases,
    seestarSupported: seestarSupported,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('proper-named bright object ranks above generic dim object', () async {
    final db = await openTestDatabase();

    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'NGC7000',
      number: 7000,
      catalog: CatalogType.ngc,
      name: '북아메리카 성운',
      commonName: '북아메리카 성운',
      mag: '4.0',
      angularSize: "120' × 100'",
      description: '백조자리의 발광성운.',
      aliases: ['North America Nebula', 'Caldwell 20'],
      seestarSupported: true,
    ).toMap());

    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'NGC9999',
      number: 9999,
      catalog: CatalogType.ngc,
      name: '발광성운',
      commonName: '발광성운',
      mag: '13.5',
    ).toMap());

    await CatalogFeaturedRankingService.apply(db);

    final famous = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: ['NGC7000'],
    )).single;
    final generic = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: ['NGC9999'],
    )).single;

    expect(
      famous[DatabaseConstants.colDisplayPriority] as int,
      lessThan(generic[DatabaseConstants.colDisplayPriority] as int),
    );
    expect(famous[DatabaseConstants.colDisplayPriority], 1);
    expect(famous[DatabaseConstants.colIsFeatured], 1);
    await db.close();
  });

  test('Messier objects keep default priority and are not featured', () async {
    final db = await openTestDatabase();

    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'M31',
      number: 31,
      catalog: CatalogType.messier,
      name: '안드로메다 은하',
      commonName: '안드로메다 은하',
      objectType: '은하',
      mag: '3.4',
      seestarSupported: true,
    ).toMap());

    await CatalogFeaturedRankingService.apply(db);

    final m31 = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: ['M31'],
    )).single;

    expect(
      m31[DatabaseConstants.colDisplayPriority],
      DatabaseConstants.defaultDisplayPriority,
    );
    expect(m31[DatabaseConstants.colIsFeatured], 0);
    await db.close();
  });

  test('priority is assigned per catalog independently', () async {
    final db = await openTestDatabase();

    for (var i = 0; i < 3; i++) {
      await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
        id: 'NGC${100 + i}',
        number: 100 + i,
        catalog: CatalogType.ngc,
        name: 'ngc-$i',
        mag: '${5 + i}',
      ).toMap());
      await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
        id: 'IC${100 + i}',
        number: 100 + i,
        catalog: CatalogType.ic,
        name: 'ic-$i',
        mag: '${5 + i}',
      ).toMap());
    }

    await CatalogFeaturedRankingService.apply(db);

    final ngcPriorities = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [DatabaseConstants.colDisplayPriority],
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: ['ngc'],
    ))
        .map((r) => r[DatabaseConstants.colDisplayPriority] as int)
        .toList()
      ..sort();
    final icPriorities = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [DatabaseConstants.colDisplayPriority],
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: ['ic'],
    ))
        .map((r) => r[DatabaseConstants.colDisplayPriority] as int)
        .toList()
      ..sort();

    expect(ngcPriorities, [1, 2, 3]);
    expect(icPriorities, [1, 2, 3]);
    await db.close();
  });

  test('aliases_json is parsed for alias-count scoring', () async {
    final db = await openTestDatabase();

    // 별칭이 많은 대상 (직접 aliases_json 삽입)
    final many = _obj(
      id: 'IC1',
      number: 1,
      catalog: CatalogType.ic,
      name: 'test-many',
      mag: '9.0',
    ).toMap();
    many[DatabaseConstants.colAliasesJson] =
        jsonEncode(['a', 'b', 'c', 'd', 'e', 'f']);
    await db.insert(DatabaseConstants.tableCelestialObjects, many);

    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'IC2',
      number: 2,
      catalog: CatalogType.ic,
      name: 'test-few',
      mag: '9.0',
    ).toMap());

    await CatalogFeaturedRankingService.apply(db);

    final withAliases = (await db.query(
      DatabaseConstants.tableCelestialObjects,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: ['IC1'],
    )).single;

    expect(withAliases[DatabaseConstants.colDisplayPriority], 1);
    await db.close();
  });

  test('FTS search returns featured object first among equal matches',
      () async {
    final db = await openTestDatabase();

    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'NGC7000',
      number: 7000,
      catalog: CatalogType.ngc,
      name: '북아메리카 성운',
      commonName: '북아메리카 성운',
      mag: '4.0',
      angularSize: "120' × 100'",
      description: '백조자리의 발광성운.',
      seestarSupported: true,
    ).toMap());
    await db.insert(DatabaseConstants.tableCelestialObjects, _obj(
      id: 'NGC1',
      number: 1,
      catalog: CatalogType.ngc,
      name: '이름없는 성운',
      commonName: '이름없는 성운',
      mag: '14.0',
    ).toMap());

    await CatalogFeaturedRankingService.apply(db);
    await CatalogFtsService.rebuild(db);

    final ids = await CatalogFtsService.searchObjectIds(db, '성운');
    expect(ids, isNotEmpty,
        reason: 'FTS 조인 쿼리가 실패하면 빈 목록이 반환된다');
    expect(ids, contains('NGC7000'));
    expect(ids, contains('NGC1'));
    await db.close();
  });
}
