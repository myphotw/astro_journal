import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/database/app_database.dart';
import 'package:astro_journal/data/datasources/equipment_local_datasource.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_capture_capability.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_remote.dart';
import 'package:astro_journal/services/equipment/equipment_capture_presets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('generalized capture capability round-trips through Equipment map', () {
    const capability = EquipmentCaptureCapability(
      modes: [
        EquipmentCaptureModeCapability(
          id: EquipmentCaptureModeCapability.altAzDerotatedId,
          type: EquipmentCaptureModeType.altAzDerotated,
          label: 'AZ 센서 회전 보정',
          exposureCapability: FreeInputExposureCapability(
            minSeconds: 30,
            maxSeconds: 300,
          ),
        ),
      ],
      gainCapability: RangeGainCapability(min: 0, max: 240, step: 10),
      filters: [
        EquipmentFilterCapability(
          id: 'dual_ho',
          type: EquipmentFilterType.dualBand,
          name: 'HO 듀얼밴드',
        ),
      ],
      channelCombinations: [
        EquipmentChannelCombinationCapability(
          id: 'sho',
          name: 'SHO',
          primaryLabel: 'SO',
          secondaryLabel: 'HO',
          ratioAdjustable: true,
          minPrimaryPercent: 0,
          maxPrimaryPercent: 100,
          stepPercent: 1,
        ),
      ],
    );
    const equipment = Equipment(
      id: 'draco',
      name: 'Draco',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      captureCapability: capability,
    );

    final restored = Equipment.fromMap(equipment.toMap());
    final profile = restored.captureCapability!;

    expect(profile.modes.single.type, EquipmentCaptureModeType.altAzDerotated);
    expect(
      profile.supportsExposure(
        EquipmentCaptureModeCapability.altAzDerotatedId,
        31.5,
      ),
      isTrue,
    );
    expect(
      profile.supportsExposure(
        EquipmentCaptureModeCapability.altAzDerotatedId,
        301,
      ),
      isFalse,
    );
    expect(profile.gainCapability!.supports(120), isTrue);
    expect(profile.gainCapability!.supports(125), isFalse);
    expect(
      profile.channelCombinations.single.isValidRatio(
        primaryPercent: 37,
        secondaryPercent: 63,
      ),
      isTrue,
    );
    expect(
      profile.channelCombinations.single.isValidRatio(
        primaryPercent: 37,
        secondaryPercent: 62,
      ),
      isFalse,
    );
  });

  test('legacy AZ and EQ exposure fields project into generalized modes', () {
    const equipment = Equipment(
      id: 'legacy',
      name: 'Legacy',
      kind: EquipmentKind.other,
      purpose: EquipmentPurpose.imaging,
      azExposureCapability: DiscreteExposureCapability(valuesSeconds: [5, 10]),
      eqExposureCapability: RangeExposureCapability(
        minSeconds: 30,
        maxSeconds: 300,
        stepSeconds: 30,
      ),
    );

    final profile = equipment.effectiveCaptureCapability!;
    expect(profile.modes, hasLength(2));
    expect(
      profile.supportsExposure(EquipmentCaptureModeCapability.altAzId, 10),
      isTrue,
    );
    expect(
      profile.supportsExposure(EquipmentCaptureModeCapability.equatorialId, 45),
      isFalse,
    );
    expect(
      profile.supportsExposure(EquipmentCaptureModeCapability.equatorialId, 60),
      isTrue,
    );
  });

  test('Seestar and Draco presets remain editable capability values', () {
    final seestar = EquipmentCapturePresets.build(
      EquipmentCapturePreset.seestarS30Pro,
    );
    final draco = EquipmentCapturePresets.build(EquipmentCapturePreset.draco);

    expect(
      seestar.modes.map((item) => item.id),
      containsAll([
        EquipmentCaptureModeCapability.altAzId,
        EquipmentCaptureModeCapability.equatorialId,
      ]),
    );
    expect(
      seestar.supportsExposure(EquipmentCaptureModeCapability.altAzId, 20),
      isTrue,
    );
    expect(seestar.gainCapability, isNull);
    expect(
      draco.modes.map((item) => item.id),
      contains(EquipmentCaptureModeCapability.altAzDerotatedId),
    );
    expect(draco.gainCapability!.supports(2), isTrue);
    expect(draco.gainCapability!.supports(7), isFalse);
    expect(draco.filters.map((item) => item.name), contains('SHO'));
    expect(draco.channelCombinations.single.stepPercent, 1);
  });

  test('invalid unsupported capability values are rejected', () {
    const invalidExposure = EquipmentCaptureCapability(
      modes: [
        EquipmentCaptureModeCapability(
          id: 'bad',
          type: EquipmentCaptureModeType.custom,
          label: 'Bad',
          exposureCapability: RangeExposureCapability(
            minSeconds: 60,
            maxSeconds: 30,
            stepSeconds: 0,
          ),
        ),
      ],
    );
    const invalidRatio = EquipmentCaptureCapability(
      channelCombinations: [
        EquipmentChannelCombinationCapability(
          id: 'bad-ratio',
          name: 'Bad ratio',
          primaryLabel: 'S',
          secondaryLabel: 'H',
          ratioAdjustable: true,
          minPrimaryPercent: 0,
          maxPrimaryPercent: 101,
          stepPercent: 0,
        ),
      ],
    );

    expect(invalidExposure.validate, throwsArgumentError);
    expect(invalidRatio.validate, throwsArgumentError);
  });

  test(
    'SQLite insert update reload and delete preserve extended capability',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await AppDatabase.createForTest(db, DatabaseConstants.databaseVersion);
      final source = EquipmentLocalDataSource(database: db);
      final capability = EquipmentCapturePresets.build(
        EquipmentCapturePreset.draco,
      );
      final equipment = Equipment(
        id: 'draco-local',
        name: 'Draco',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        focalLengthMm: 250,
        fovWidthDegrees: 2,
        fovHeightDegrees: 3,
        captureCapability: capability,
      );

      await source.insert(equipment);
      await source.update(equipment.copyWith(name: 'Draco renamed'));
      final restored = await source.getById(equipment.id);

      expect(restored!.name, 'Draco renamed');
      expect(restored.captureCapability!.modes, hasLength(2));
      expect(
        restored.captureCapability!.filters.map((item) => item.name),
        contains('SHO'),
      );

      await source.delete(equipment.id);
      expect(await source.getById(equipment.id), isNull);
    },
  );

  test(
    'remote aggregate excludes local extension and pull preserves it',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await AppDatabase.createForTest(db, DatabaseConstants.databaseVersion);
      final source = EquipmentLocalDataSource(database: db);
      final local = Equipment(
        id: 'shared-id',
        name: 'Local name',
        kind: EquipmentKind.smartTelescope,
        purpose: EquipmentPurpose.imaging,
        captureCapability: EquipmentCapturePresets.build(
          EquipmentCapturePreset.draco,
        ),
      );
      await source.insert(local);
      final remote = EquipmentRemoteAggregate(
        equipment: const Equipment(
          id: 'shared-id',
          name: 'Server name',
          kind: EquipmentKind.smartTelescope,
          purpose: EquipmentPurpose.imaging,
        ),
        revision: 2,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      expect(remote.toJson(), isNot(contains('capture_capability')));
      await source.applyRemoteAggregate(remote, force: true);
      final restored = await source.getById('shared-id');

      expect(restored!.name, 'Server name');
      expect(
        restored.captureCapability!.filters.map((item) => item.name),
        contains('SHO'),
      );
    },
  );

  test(
    'v35 migration adds nullable capture capability without changing rows',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
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
        sort_order INTEGER NOT NULL DEFAULT 0,
        az_exposure_capability_json TEXT,
        eq_exposure_capability_json TEXT
      )
    ''');
      await db.insert('equipment', {
        'id': 'existing',
        'name': 'Existing',
        'equipment_kind': 'other',
        'equipment_purpose': 'imaging',
      });

      await AppDatabase.migrateForTest(db, 35, 36);

      final columns = await db.rawQuery('PRAGMA table_info(equipment)');
      expect(
        columns.map((item) => item['name']),
        contains(DatabaseConstants.colCaptureCapabilityJson),
      );
      final rows = await db.query('equipment');
      expect(rows, hasLength(1));
      expect(rows.single[DatabaseConstants.colCaptureCapabilityJson], isNull);
    },
  );
}
