import 'package:sqflite/sqflite.dart' show Database;

/// Creates the Equipment portion of a v16-v33 database fixture.
///
/// v15 introduced `equipment` and `eyepieces`; v16 added the two FOV axis
/// columns. The v34 exposure capability columns and sync tables deliberately
/// do not belong in this legacy schema.
Future<void> createLegacyEquipmentTables(
  Database db, {
  bool seedRows = false,
}) async {
  await db.execute('''
    CREATE TABLE equipment (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      equipment_kind TEXT NOT NULL,
      equipment_purpose TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      focal_length_mm REAL,
      fov_degrees REAL,
      fov_width_degrees REAL,
      fov_height_degrees REAL,
      aperture_mm REAL,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE eyepieces (
      id TEXT PRIMARY KEY,
      equipment_id TEXT NOT NULL,
      name TEXT NOT NULL,
      focal_length_mm REAL NOT NULL,
      afov_degrees REAL NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (equipment_id) REFERENCES equipment (id) ON DELETE CASCADE
    )
  ''');
  if (!seedRows) return;
  await db.insert('equipment', {
    'id': 'legacy-equipment',
    'name': 'Legacy Equipment',
    'equipment_kind': 'reflector',
    'equipment_purpose': 'visual',
    'is_active': 1,
    'focal_length_mm': 500,
    'fov_degrees': 2.5,
    'fov_width_degrees': 2.5,
    'fov_height_degrees': 2.5,
    'aperture_mm': 90,
    'sort_order': 0,
  });
  await db.insert('eyepieces', {
    'id': 'legacy-eyepiece',
    'equipment_id': 'legacy-equipment',
    'name': '25mm',
    'focal_length_mm': 25,
    'afov_degrees': 60,
    'sort_order': 0,
  });
}
