import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, String> _loadIdRemap() {
  final raw =
      jsonDecode(File('assets/catalog/id_remap.json').readAsStringSync())
          as Map<String, dynamic>;
  return raw.map((key, value) => MapEntry(key, value as String));
}

Map<String, dynamic> _loadJsonMap(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _loadJsonObjects(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

String _resolveCanonical(String id, Map<String, String> remap) {
  var current = id;
  final visited = <String>{};
  while (remap[current] != null) {
    final next = remap[current]!;
    if (!visited.add(current)) {
      fail('catalog id remap cycle detected at $current');
    }
    current = next;
  }
  return current;
}

Set<String> _metadataTokens(Map<String, Object?> row) {
  final result = <String>{};
  for (final column in ['aliases_json', 'cross_catalog_refs_json']) {
    final raw = row[column] as String?;
    if (raw == null || raw.isEmpty) continue;
    result.addAll((jsonDecode(raw) as List<dynamic>).cast<String>());
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('catalog identity regression', () {
    test('Barnard and Helix identifiers resolve to separate canonicals', () {
      final remap = _loadIdRemap();
      final barnard = {
        for (final id in ['NGC6822', 'IC4895', 'C57'])
          _resolveCanonical(id, remap),
      };
      final helix = {
        for (final id in ['NGC7293', 'C63']) _resolveCanonical(id, remap),
      };

      expect(barnard, {'NGC6822'});
      expect(helix, {'NGC7293'});
      expect(barnard.intersection(helix), isEmpty);
    });

    test('seed metadata keeps Barnard and Helix groups isolated', () async {
      final dbPath = File('assets/database/catalog_seed.db').absolute.path;
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(db.close);

      Future<Map<String, Object?>> row(String id) async {
        final rows = await db.query(
          'celestial_objects',
          where: 'id = ?',
          whereArgs: [id],
        );
        expect(rows, hasLength(1), reason: 'missing seed object $id');
        return rows.single;
      }

      final ngc6822 = await row('NGC6822');
      final ic4895 = await row('IC4895');
      final ngc7293 = await row('NGC7293');

      expect(ngc6822['object_type'], contains('은하'));
      expect(ic4895['object_type'], contains('은하'));
      expect(ngc7293['object_type'], '행성상성운');
      expect(ic4895['primary_catalog_id'], 'NGC6822');

      final barnardTokens = {
        ..._metadataTokens(ngc6822),
        ..._metadataTokens(ic4895),
      };
      final helixTokens = _metadataTokens(ngc7293);

      expect(barnardTokens, isNot(contains('C63')));
      expect(barnardTokens, isNot(contains('C 063')));
      expect(barnardTokens, isNot(contains('Helix Nebula')));
      expect(helixTokens, isNot(contains('C57')));
      expect(helixTokens, isNot(contains('C 057')));
      expect(helixTokens, isNot(contains("Barnard's Galaxy")));
      expect(helixTokens, isNot(contains('IC4895')));
      expect(helixTokens, isNot(contains('NGC6822')));
    });

    test('M42 keeps the NGC1976 cross-catalog identity', () {
      final equivalence = _loadJsonMap(
        'assets/catalog/catalog_equivalence.json',
      );
      final messierNgc = equivalence['messierNgc'] as Map<String, dynamic>;
      final messier = _loadJsonObjects('assets/catalog/messier.json');
      final m42 = messier.singleWhere((item) => item['id'] == 'M42');
      final crossRefs = (m42['crossCatalogRefs'] as List<dynamic>)
          .cast<String>();

      expect(messierNgc['1976'], 42);
      expect(crossRefs, contains('NGC 1976'));
    });

    test('NGC2024 has no M42 identity remap', () {
      final equivalence = _loadJsonMap(
        'assets/catalog/catalog_equivalence.json',
      );
      final messierNgc = equivalence['messierNgc'] as Map<String, dynamic>;
      final embeddedRemap = equivalence['idRemap'] as Map<String, dynamic>;
      final groups = (equivalence['groups'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final idRemap = _loadIdRemap();
      final messier = _loadJsonObjects('assets/catalog/messier.json');
      final m42 = messier.singleWhere((item) => item['id'] == 'M42');
      final aliases = (m42['aliases'] as List<dynamic>).cast<String>();
      final crossRefs = (m42['crossCatalogRefs'] as List<dynamic>)
          .cast<String>();
      final ngc2024Group = groups.singleWhere(
        (group) => (group['members'] as List<dynamic>).contains('NGC2024'),
      );

      expect(messierNgc.containsKey('2024'), isFalse);
      expect(embeddedRemap.containsKey('NGC2024'), isFalse);
      expect(idRemap.containsKey('NGC2024'), isFalse);
      expect(ngc2024Group['canonicalId'], 'NGC2024');
      expect(ngc2024Group['members'], ['NGC2024']);
      expect(crossRefs, isNot(contains('NGC2024')));
      expect(aliases, isNot(contains('NGC2024')));
    });

    test('seed keeps M42 and NGC2024 as independent primary objects', () async {
      final dbPath = File('assets/database/catalog_seed.db').absolute.path;
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(db.close);

      final rows = await db.query(
        'celestial_objects',
        where: 'id IN (?, ?)',
        whereArgs: ['M42', 'NGC2024'],
      );
      expect(rows, hasLength(2));
      final m42 = rows.singleWhere((row) => row['id'] == 'M42');
      final ngc2024 = rows.singleWhere((row) => row['id'] == 'NGC2024');
      final m42Tokens = _metadataTokens(m42);
      final ngc2024Tokens = _metadataTokens(ngc2024);

      expect(m42['is_primary_catalog'], 1);
      expect(m42['primary_catalog_id'], isNull);
      expect(ngc2024['is_primary_catalog'], 1);
      expect(ngc2024['primary_catalog_id'], isNull);
      expect(m42Tokens, contains('NGC 1976'));
      expect(m42Tokens, isNot(contains('NGC2024')));
      expect(m42Tokens, isNot(contains('NGC 2024')));
      expect(m42Tokens, isNot(contains('Flame Nebula')));
      expect(ngc2024Tokens, contains('Flame Nebula'));
      expect(ngc2024Tokens, contains('Sh2-277'));
      expect(ngc2024['ra'], isNot(m42['ra']));
    });

    test('NGC2024 remains independently searchable in catalog assets', () async {
      final seestar = _loadJsonObjects('assets/catalog/seestar_catalog.json');
      final messier = _loadJsonObjects('assets/catalog/messier.json');
      final ngc2024 = seestar.singleWhere((item) => item['id'] == 'NGC2024');
      final m42 = messier.singleWhere((item) => item['id'] == 'M42');
      expect(ngc2024['aliases'], contains('Flame Nebula'));
      expect(ngc2024['ra'], isNot(m42['ra']));

      final dbPath = File('assets/database/catalog_seed.db').absolute.path;
      final db = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(db.close);
      final rows = await db.query(
        'celestial_objects',
        columns: ['id', 'search_keywords'],
        where: 'id = ?',
        whereArgs: ['NGC2024'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['search_keywords'], contains('NGC2024'));
      expect(rows.single['search_keywords'], contains('Flame Nebula'));
    });
  });
}
