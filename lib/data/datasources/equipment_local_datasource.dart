import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;

import '../../core/constants/database_constants.dart';
import '../database/app_database.dart';
import '../models/equipment.dart';
import '../models/eyepiece.dart';

class EquipmentLocalDataSource {
  EquipmentLocalDataSource({this._database});

  Database? _database;

  Future<Database> get _db async {
    _database = await AppDatabase.resolve(_database);
    return _database!;
  }

  Future<List<Equipment>> getAll({bool activeOnly = false}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableEquipment,
      where: activeOnly ? '${DatabaseConstants.colIsActive} = 1' : null,
      orderBy: '${DatabaseConstants.colSortOrder}, ${DatabaseConstants.colName}',
    );
    if (rows.isEmpty) return [];

    final equipmentIds =
        rows.map((row) => row[DatabaseConstants.colId] as String).toList();
    final eyepiecesByEquipment =
        await _getEyepiecesGroupedByEquipment(db, equipmentIds);

    return rows
        .map(
          (row) => Equipment.fromMap(
            row,
            eyepieces:
                eyepiecesByEquipment[row[DatabaseConstants.colId] as String] ??
                    const [],
          ),
        )
        .toList();
  }

  Future<Equipment?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseConstants.tableEquipment,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final eyepieces = await _getEyepiecesForEquipment(db, id);
    return Equipment.fromMap(rows.first, eyepieces: eyepieces);
  }

  Future<void> insert(Equipment equipment) async {
    final db = await _db;
    await db.insert(
      DatabaseConstants.tableEquipment,
      equipment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final eyepiece in equipment.eyepieces) {
      await db.insert(
        DatabaseConstants.tableEyepieces,
        eyepiece.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> update(Equipment equipment) async {
    final db = await _db;
    await db.update(
      DatabaseConstants.tableEquipment,
      equipment.toMap(),
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [equipment.id],
    );
    await db.delete(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} = ?',
      whereArgs: [equipment.id],
    );
    for (final eyepiece in equipment.eyepieces) {
      await db.insert(
        DatabaseConstants.tableEyepieces,
        eyepiece.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} = ?',
      whereArgs: [id],
    );
    await db.delete(
      DatabaseConstants.tableEquipment,
      where: '${DatabaseConstants.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<List<Eyepiece>> _getEyepiecesForEquipment(
    Database db,
    String equipmentId,
  ) async {
    final grouped = await _getEyepiecesGroupedByEquipment(db, [equipmentId]);
    return grouped[equipmentId] ?? const [];
  }

  Future<Map<String, List<Eyepiece>>> _getEyepiecesGroupedByEquipment(
    Database db,
    List<String> equipmentIds,
  ) async {
    if (equipmentIds.isEmpty) return {};

    final placeholders = List.filled(equipmentIds.length, '?').join(', ');
    final rows = await db.query(
      DatabaseConstants.tableEyepieces,
      where: '${DatabaseConstants.colEquipmentId} IN ($placeholders)',
      whereArgs: equipmentIds,
      orderBy:
          '${DatabaseConstants.colSortOrder}, ${DatabaseConstants.colFocalLengthMm}',
    );

    final grouped = <String, List<Eyepiece>>{};
    for (final row in rows) {
      final eyepiece = Eyepiece.fromMap(row);
      (grouped[eyepiece.equipmentId] ??= []).add(eyepiece);
    }
    return grouped;
  }
}
