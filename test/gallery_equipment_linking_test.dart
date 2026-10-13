import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/models/gallery_equipment_selection.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/gallery/widgets/gallery_equipment_selector.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gallery equipment link state', () {
    test('legacy equipment name remains unlinked without name matching', () {
      final selection = GalleryEquipmentSelection.fromExif(
        _exif(equipment: 'Same name'),
      );

      expect(selection.displayName, 'Same name');
      expect(selection.equipmentId, isNull);
      expect(selection.wasExplicitlyChanged, isFalse);
    });

    test(
      'explicit selection stores the selected UUID even for equal names',
      () {
        final selection = GalleryEquipmentSelection.fromExif(
          _exif(equipment: 'Legacy'),
        ).select(_equipmentB);

        expect(selection.equipmentId, _equipmentB.id);
        expect(selection.displayName, 'Same name');
        expect(selection.wasExplicitlyChanged, isTrue);
      },
    );

    test('unlink preserves the latest displayed equipment name', () {
      final selection = GalleryEquipmentSelection.fromExif(
        _exif(equipment: 'Renamed', equipmentId: _equipmentA.id),
      ).unlink();

      expect(selection.equipmentId, isNull);
      expect(selection.displayName, 'Renamed');
      expect(selection.wasExplicitlyChanged, isTrue);
    });

    test('missing or deleted equipment falls back to the stored snapshot', () {
      final record = _record(
        _exif(
          equipment: '',
          equipmentId: 'deleted-id',
          snapshot: 'Deleted equipment',
        ),
      );

      final resolved = resolveGalleryEquipmentName(record, const {});

      expect(resolved.equipmentId, 'deleted-id');
      expect(resolved.exif?.equipment, 'Deleted equipment');
    });
  });

  test(
    'Gallery list and detail use the same latest local equipment name',
    () async {
      final records = _RecordRepository([
        _record(
          _exif(
            equipment: 'Server snapshot',
            equipmentId: _equipmentA.id,
            snapshot: 'Server snapshot',
          ),
        ),
      ]);
      final equipment = _EquipmentRepository([_equipmentA]);
      final viewModel = GalleryViewModel(
        records,
        _CatalogRepository(),
        CatalogSearchService(),
        equipmentRepository: equipment,
      );

      await viewModel.load();
      expect(viewModel.recordForId('record-1')?.exif?.equipment, 'Same name');
      expect(
        (await viewModel.loadDetailRecord(
          records.items.single,
        )).exif?.equipment,
        'Same name',
      );

      equipment.items = [_equipmentA.copyWith(name: 'Renamed locally')];
      await viewModel.refreshEquipmentDisplayNames();

      expect(
        viewModel.recordForId('record-1')?.exif?.equipment,
        'Renamed locally',
      );
      expect(records.updateCalls, 0);
    },
  );

  test(
    'same legacy name is not automatically connected by Gallery load',
    () async {
      final records = _RecordRepository([
        _record(_exif(equipment: 'Same name')),
      ]);
      final viewModel = GalleryViewModel(
        records,
        _CatalogRepository(),
        CatalogSearchService(),
        equipmentRepository: _EquipmentRepository([_equipmentA]),
      );

      await viewModel.load();

      expect(viewModel.recordForId('record-1')?.equipmentId, isNull);
      expect(viewModel.recordForId('record-1')?.exif?.equipment, 'Same name');
    },
  );

  testWidgets(
    'selector distinguishes duplicate UUIDs and excludes inactive equipment',
    (tester) async {
      Equipment? selected;
      var unlinked = false;
      final selection = GalleryEquipmentSelection.fromExif(
        _exif(equipment: 'Same name', equipmentId: _equipmentA.id),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GalleryEquipmentSelector(
              selection: selection,
              equipment: const [_equipmentA, _equipmentB, _inactiveEquipment],
              onSelected: (value) => selected = value,
              onUnlink: () => unlinked = true,
            ),
          ),
        ),
      );

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      final items = dropdown.items!;
      final values = items.map((item) => item.value).toList(growable: false);
      final labels = items
          .map((item) => (item.child as Text).data)
          .toList(growable: false);

      expect(values, [_equipmentA.id, _equipmentB.id]);
      expect(values.toSet(), hasLength(2));
      expect(values, isNot(contains(_inactiveEquipment.id)));
      expect(labels, ['Same name · 11111111', 'Same name · 22222222']);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(ValueKey('gallery-equipment-option-${_equipmentB.id}')),
      );
      await tester.pumpAndSettle();
      expect(selected?.id, _equipmentB.id);

      await tester.tap(find.byKey(const Key('gallery-equipment-unlink')));
      expect(unlinked, isTrue);
    },
  );

  testWidgets('inactive linked equipment remains visible through fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryEquipmentSelector(
            selection: GalleryEquipmentSelection.fromExif(
              _exif(
                equipment: 'Inactive equipment',
                equipmentId: _inactiveEquipment.id,
              ),
            ),
            equipment: const [_inactiveEquipment],
            currentIsActive: false,
            onSelected: (_) {},
            onUnlink: () {},
          ),
        ),
      ),
    );

    expect(find.text('현재 장비: Inactive equipment (비활성 또는 삭제됨)'), findsOneWidget);
    expect(find.byKey(const Key('gallery-equipment-unlink')), findsOneWidget);
  });
}

const _equipmentA = Equipment(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Same name',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

const _equipmentB = Equipment(
  id: '22222222-2222-4222-8222-222222222222',
  name: 'Same name',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

const _inactiveEquipment = Equipment(
  id: '33333333-3333-4333-8333-333333333333',
  name: 'Inactive equipment',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
  isActive: false,
);

ExifInfo _exif({
  required String equipment,
  String? equipmentId,
  String? snapshot,
}) => ExifInfo.placeholder(filename: 'photo.jpg').copyWith(
  equipment: equipment,
  equipmentId: equipmentId,
  equipmentNameSnapshot: snapshot,
);

ShootingRecord _record(ExifInfo exif) => ShootingRecord(
  id: 'record-1',
  celestialObjectId: 'M31',
  capturedAt: DateTime(2026, 10, 13),
  createdAt: DateTime(2026, 10, 13),
  exif: exif,
);

class _RecordRepository implements ShootingRecordRepository {
  _RecordRepository(this.items);

  final List<ShootingRecord> items;
  int updateCalls = 0;

  @override
  Future<List<ShootingRecord>> getAll() async => List.of(items);

  @override
  Future<ShootingRecord?> getById(String id) async =>
      items.where((item) => item.id == id).firstOrNull;

  @override
  Future<void> update(ShootingRecord record) async {
    updateCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EquipmentRepository implements EquipmentRepository {
  _EquipmentRepository(this.items);

  List<Equipment> items;

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => activeOnly
      ? items.where((item) => item.isActive).toList()
      : List.of(items);

  @override
  Future<Equipment?> getById(String id) async =>
      items.where((item) => item.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => const [
    CatalogObject(
      id: 'M31',
      number: 31,
      catalog: CatalogType.messier,
      name: 'Andromeda',
      type: 'Galaxy',
      constellation: 'Andromeda',
      ra: '-',
      dec: '-',
      magnitude: '3.4',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
