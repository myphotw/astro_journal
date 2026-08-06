import 'package:astro_journal/services/tonight_shooting_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TonightShootingPlanService service;
  final planDate = DateTime(2026, 7, 7);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = TonightShootingPlanService();
  });

  test('loadSnapshotForDate returns empty snapshot when nothing saved', () async {
    final snapshot = await service.loadSnapshotForDate(planDate);
    expect(snapshot.orderedObjectIds, isEmpty);
    expect(snapshot.userEdited, isFalse);
  });

  test('saveOrderedForDate persists order and userEdited flag', () async {
    await service.saveOrderedForDate(
      planDate,
      ['m42', 'm31'],
      userEdited: false,
    );

    final snapshot = await service.loadSnapshotForDate(planDate);
    expect(snapshot.orderedObjectIds, ['m42', 'm31']);
    expect(snapshot.userEdited, isFalse);
  });

  test('add appends id and marks plan as user edited', () async {
    await service.saveOrderedForDate(planDate, ['m31'], userEdited: false);
    await service.add(planDate, 'm42');

    final snapshot = await service.loadSnapshotForDate(planDate);
    expect(snapshot.orderedObjectIds, ['m31', 'm42']);
    expect(snapshot.userEdited, isTrue);
  });

  test('add ignores duplicate ids', () async {
    await service.add(planDate, 'm31');
    await service.add(planDate, 'm31');
    expect(
      (await service.loadSnapshotForDate(planDate)).orderedObjectIds,
      ['m31'],
    );
  });

  test('remove deletes object id from ordered plan', () async {
    await service.saveOrderedForDate(
      planDate,
      ['m31', 'm42'],
      userEdited: true,
    );
    await service.remove(planDate, 'm31');

    expect(
      (await service.loadSnapshotForDate(planDate)).orderedObjectIds,
      ['m42'],
    );
  });

  test('plans are isolated by date', () async {
    await service.saveOrderedForDate(planDate, ['m31'], userEdited: false);
    await service.saveOrderedForDate(
      DateTime(2026, 7, 8),
      ['m42'],
      userEdited: true,
    );

    expect(
      (await service.loadSnapshotForDate(planDate)).orderedObjectIds,
      ['m31'],
    );
    expect(
      (await service.loadSnapshotForDate(DateTime(2026, 7, 8))).orderedObjectIds,
      ['m42'],
    );
  });
}
