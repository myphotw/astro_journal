import 'package:sqflite/sqflite.dart';

import '../core/constants/database_constants.dart';
import '../data/models/catalog_object.dart';
import 'catalog_fts_service.dart';
import 'object_type_classifier.dart';

/// ObjectType 재분류 + 암흑성운 제거 (기존 설치 DB용).
class CatalogObjectTypeMigration {
  CatalogObjectTypeMigration._();

  static const _classifier = ObjectTypeClassifier();

  static Future<({int reclassified, int removedDark})> apply(
    Database db, {
    Map<String, List<String>> globalAliases = const {},
    Map<String, List<String>> globalCrossCatalog = const {},
  }) async {
    final rows = await db.query(DatabaseConstants.tableCelestialObjects);
    if (rows.isEmpty) {
      return (reclassified: 0, removedDark: 0);
    }

    var reclassified = 0;
    final darkIds = <String>[];

    await db.transaction((txn) async {
      for (final row in rows) {
        final object = CatalogObject.fromMap(row);
        if (_classifier.isDarkNebulaTarget(
          catalog: object.catalog.value,
          objectType: object.objectType,
          type: object.type,
          name: object.name,
          commonName: object.commonName,
          description: object.description,
          aliases: object.aliases,
        )) {
          darkIds.add(object.id);
          continue;
        }

        final classified = _classifier.classify(
          id: object.id,
          catalog: object.catalog.value,
          name: object.name,
          commonName: object.commonName,
          objectType: object.objectType,
          type: object.type,
          description: object.description,
          aliases: object.aliases,
        );
        final label = classified.label;
        final current = (object.objectType ?? object.type).trim();
        if (label == current) continue;

        reclassified++;
        await txn.update(
          DatabaseConstants.tableCelestialObjects,
          {
            DatabaseConstants.colObjectType: label,
            DatabaseConstants.colType: label,
          },
          where: '${DatabaseConstants.colId} = ?',
          whereArgs: [object.id],
        );
      }

      if (darkIds.isNotEmpty) {
        final placeholders = List.filled(darkIds.length, '?').join(', ');
        // 촬영 기록은 유지 (카탈로그 행만 삭제)
        await txn.delete(
          DatabaseConstants.tableCelestialObjects,
          where: '${DatabaseConstants.colId} IN ($placeholders)',
          whereArgs: darkIds,
        );
      }
    });

    if (reclassified > 0 || darkIds.isNotEmpty) {
      await CatalogFtsService.rebuild(
        db,
        globalAliases: globalAliases,
        globalCrossCatalog: globalCrossCatalog,
      );
    }

    return (reclassified: reclassified, removedDark: darkIds.length);
  }
}
