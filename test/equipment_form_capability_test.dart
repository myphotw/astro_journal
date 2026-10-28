import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/features/settings/view/equipment_form_screen.dart';
import 'package:astro_journal/features/settings/viewmodel/equipment_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('editing legacy equipment preserves AZ and EQ capabilities', (
    tester,
  ) async {
    const original = Equipment(
      id: 'existing',
      name: 'Existing smart telescope',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 250,
      fovWidthDegrees: 2,
      fovHeightDegrees: 3,
      azExposureCapability: DiscreteExposureCapability(
        valuesSeconds: [5, 10, 20],
      ),
      eqExposureCapability: RangeExposureCapability(
        minSeconds: 30,
        maxSeconds: 300,
        stepSeconds: 30,
      ),
    );
    final repository = _MemoryEquipmentRepository([original]);
    final viewModel = EquipmentViewModel(repository);
    await viewModel.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: EquipmentFormScreen(initial: original)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('equipment-capture-capability-editor')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('equipment-mode-alt_az')), findsOneWidget);
    expect(find.byKey(const Key('equipment-mode-equatorial')), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    final saved = repository.items.single;
    expect(
      (saved.azExposureCapability! as DiscreteExposureCapability).valuesSeconds,
      [5, 10, 20],
    );
    expect(
      (saved.eqExposureCapability! as RangeExposureCapability).maxSeconds,
      300,
    );
    expect(saved.captureCapability!.modes, hasLength(2));
  });

  testWidgets('visual equipment does not expose imaging capability editor', (
    tester,
  ) async {
    const equipment = Equipment(
      id: 'visual',
      name: 'Visual scope',
      kind: EquipmentKind.reflector,
      purpose: EquipmentPurpose.visual,
      focalLengthMm: 500,
      apertureMm: 90,
    );
    final viewModel = EquipmentViewModel(
      _MemoryEquipmentRepository([equipment]),
    );
    await viewModel.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: const MaterialApp(home: EquipmentFormScreen(initial: equipment)),
      ),
    );

    expect(
      find.byKey(const Key('equipment-capture-capability-editor')),
      findsNothing,
    );
  });
}

class _MemoryEquipmentRepository implements EquipmentRepository {
  _MemoryEquipmentRepository(List<Equipment> initial)
    : items = List<Equipment>.from(initial);

  final List<Equipment> items;

  @override
  Future<void> delete(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => items
      .where((item) => !activeOnly || item.isActive)
      .toList(growable: false);

  @override
  Future<Equipment?> getById(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> save(Equipment equipment) async {
    final index = items.indexWhere((item) => item.id == equipment.id);
    if (index < 0) {
      items.add(equipment);
    } else {
      items[index] = equipment;
    }
  }
}
