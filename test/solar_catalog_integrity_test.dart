import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/formatters/catalog_object_display_formatter.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_display_name_resolver.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late List<CatalogObject> solar;
  late CatalogObject m8;

  setUpAll(() async {
    solar = _loadCatalog('assets/catalog/solar.json', CatalogType.solar);
    m8 = _loadCatalog(
      'assets/catalog/messier.json',
      CatalogType.messier,
    ).singleWhere((object) => object.id == 'M8');
    await CatalogDisplayNameResolver.load();
  });

  tearDown(CatalogSearchService.invalidateIndex);

  test('all built-in Solar targets have authoritative identity and type', () {
    const expected = <String, (String, String, String)>{
      'solar_1': ('태양', 'Sun', '항성'),
      'solar_2': ('달', 'Moon', '위성'),
      'solar_3': ('수성', 'Mercury', '행성'),
      'solar_4': ('금성', 'Venus', '행성'),
      'solar_5': ('화성', 'Mars', '행성'),
      'solar_6': ('목성', 'Jupiter', '행성'),
      'solar_7': ('토성', 'Saturn', '행성'),
      'solar_8': ('천왕성', 'Uranus', '행성'),
      'solar_9': ('해왕성', 'Neptune', '행성'),
      'solar_10': ('명왕성', 'Pluto', '왜소행성'),
    };

    expect(solar, hasLength(14));
    expect(solar.map((object) => object.id).toSet(), hasLength(solar.length));
    expect(
      solar.map((object) => object.number).toSet(),
      hasLength(solar.length),
    );
    expect(solar.map((object) => object.name).toSet(), hasLength(solar.length));

    for (final entry in expected.entries) {
      final object = solar.singleWhere((item) => item.id == entry.key);
      expect(object.catalog, CatalogType.solar, reason: entry.key);
      expect(object.name, entry.value.$1, reason: entry.key);
      expect(object.commonName, entry.value.$1, reason: entry.key);
      expect(object.aliases, contains(entry.value.$2), reason: entry.key);
      expect(object.objectType, entry.value.$3, reason: entry.key);
      expect(object.type, entry.value.$3, reason: entry.key);
      expect(object.constellation, '-', reason: entry.key);
      expect(object.ra, '-', reason: entry.key);
      expect(object.dec, '-', reason: entry.key);
    }
  });

  test('Solar aliases contain no Messier or deep-sky metadata', () {
    final forbidden = <String>{
      'Crab Nebula',
      'Lagoon Nebula',
      'LBN 25',
      'Butterfly Cluster',
      'Ptolemy Cluster',
    };

    for (final object in solar) {
      expect(
        object.aliases.toSet().intersection(forbidden),
        isEmpty,
        reason: object.id,
      );
      expect(
        object.crossCatalogRefs.where(
          (value) => RegExp(
            r'^(M|NGC|IC|LBN|LDN|C)\s*\d+',
            caseSensitive: false,
          ).hasMatch(value),
        ),
        isEmpty,
        reason: object.id,
      );
    }
  });

  test('Uranus and M8 display identities remain separate', () {
    final uranus = solar.singleWhere((object) => object.id == 'solar_8');

    expect(uranus.displayName, '천왕성');
    expect(uranus.displayCommonName, '천왕성');
    expect(uranus.uiDisplayName, '행성');
    expect(CatalogObjectDisplayFormatter.subtitle(uranus), '행성');
    expect(uranus.aliases, ['Uranus']);
    expect(uranus.aliases, isNot(contains('Lagoon Nebula')));

    expect(m8.displayName, 'M8');
    expect(m8.objectType, '발광성운');
    expect(m8.aliases, contains('Lagoon Nebula'));
    expect(m8.uiDisplayName, '석호성운');
  });

  test('Solar and M8 search terms resolve without cross contamination', () {
    final catalog = [...solar, m8];
    final service = CatalogSearchService();

    void expectsOnly(String query, String id) {
      final results = service.search(query, catalog);
      expect(results.map((object) => object.id), contains(id), reason: query);
      if (id == 'solar_8') {
        expect(results.map((object) => object.id), isNot(contains('M8')));
      } else if (id == 'M8') {
        expect(results.map((object) => object.id), isNot(contains('solar_8')));
      }
    }

    expectsOnly('천왕성', 'solar_8');
    expectsOnly('Uranus', 'solar_8');
    expectsOnly('석호성운', 'M8');
    expectsOnly('M8', 'M8');
    expectsOnly('Lagoon Nebula', 'M8');
    expectsOnly('핼리', 'solar_11');
    expectsOnly('Halley', 'solar_11');
    expectsOnly('C/2023 A3', 'solar_14');
  });

  test('comets are record-only moving targets without fixed coordinates', () {
    final comets = solar.where((object) => object.type == '혜성').toList();

    expect(comets.map((object) => object.id), [
      'solar_11',
      'solar_12',
      'solar_13',
      'solar_14',
    ]);
    for (final comet in comets) {
      expect(comet.catalog, CatalogType.solar);
      expect(comet.objectType, '혜성');
      expect(comet.ra, '-');
      expect(comet.dec, '-');
      expect(comet.constellation, '-');
      expect(comet.tags, containsAll(['record_only', 'dynamic_ephemeris']));
    }
  });

  test('bundled seed contains only corrected Solar rows', () async {
    final db = await databaseFactoryFfi.openDatabase(
      File('assets/database/catalog_seed.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    addTearDown(db.close);

    final rows = await db.query(
      DatabaseConstants.tableCelestialObjects,
      columns: [
        DatabaseConstants.colId,
        DatabaseConstants.colName,
        DatabaseConstants.colObjectType,
        DatabaseConstants.colRa,
        DatabaseConstants.colDec,
        DatabaseConstants.colAliasesJson,
        DatabaseConstants.colCrossCatalogRefsJson,
      ],
      where: '${DatabaseConstants.colCatalog} = ?',
      whereArgs: [CatalogType.solar.value],
      orderBy: DatabaseConstants.colNum,
    );

    expect(rows, hasLength(14));
    final uranus = rows.singleWhere(
      (row) => row[DatabaseConstants.colId] == 'solar_8',
    );
    expect(uranus[DatabaseConstants.colName], '천왕성');
    expect(uranus[DatabaseConstants.colObjectType], '행성');
    expect(jsonDecode(uranus[DatabaseConstants.colAliasesJson] as String), [
      'Uranus',
    ]);
    expect(uranus[DatabaseConstants.colCrossCatalogRefsJson], isNull);

    for (final row in rows) {
      expect(row[DatabaseConstants.colRa], '-');
      expect(row[DatabaseConstants.colDec], '-');
      final aliases = row[DatabaseConstants.colAliasesJson] as String? ?? '';
      expect(aliases, isNot(contains('Lagoon Nebula')));
    }
  });

  test('catalog refresh version advances without a schema migration', () {
    expect(DatabaseConstants.databaseVersion, 32);
    expect(DatabaseConstants.catalogDataVersion, 30);
  });
}

List<CatalogObject> _loadCatalog(String path, CatalogType type) {
  final source = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  return source
      .map((item) => CatalogObject.fromJson(item as Map<String, dynamic>, type))
      .toList(growable: false);
}
