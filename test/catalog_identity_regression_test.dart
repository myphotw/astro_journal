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
  });
}
