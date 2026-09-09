import 'dart:async';
import 'dart:convert';

import '../../core/services/observation_context_invalidator.dart';
import '../../core/services/performance_probe.dart';
import '../datasources/equipment_local_datasource.dart';
import '../models/equipment.dart';
import 'equipment_repository.dart';

class EquipmentRepositoryImpl implements EquipmentRepository {
  EquipmentRepositoryImpl({
    EquipmentLocalDataSource? dataSource,
    this.contextInvalidator,
    this.onCollectionChanged,
    this.scheduleSync,
  }) : _dataSource = dataSource ?? EquipmentLocalDataSource();

  final EquipmentLocalDataSource _dataSource;
  final ObservationContextInvalidator? contextInvalidator;
  final Future<void> Function()? onCollectionChanged;
  final Future<void> Function()? scheduleSync;

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) =>
      PerformanceProbe.measureAsync(
        'db.equipment.list',
        () => _dataSource.getAll(activeOnly: activeOnly),
        state: 'active_only=$activeOnly',
      );

  @override
  Future<Equipment?> getById(String id) => _dataSource.getById(id);

  @override
  Future<void> save(Equipment equipment) async {
    final existing = await _dataSource.getById(equipment.id);
    if (existing == null) {
      await _dataSource.insert(equipment);
    } else {
      await _dataSource.update(equipment);
    }
    await onCollectionChanged?.call();
    if (_equipmentConditionsDiffer(existing, equipment)) {
      await contextInvalidator?.invalidate(ObservationContextChange.equipment);
    }
    _scheduleBackgroundSync();
  }

  @override
  Future<void> delete(String id) async {
    await _dataSource.delete(id);
    await onCollectionChanged?.call();
    await contextInvalidator?.invalidate(ObservationContextChange.equipment);
    _scheduleBackgroundSync();
  }

  void _scheduleBackgroundSync() {
    final callback = scheduleSync;
    if (callback == null) return;
    unawaited(callback().catchError((_) {}));
  }
}

bool _equipmentConditionsDiffer(Equipment? before, Equipment after) {
  if (before == null) return true;
  Object signature(Equipment value) => {
    'kind': value.kind.name,
    'purpose': value.purpose.name,
    'active': value.isActive,
    'focal': value.focalLengthMm,
    'aperture': value.apertureMm,
    'fov_width': value.fovWidthDegrees,
    'fov_height': value.fovHeightDegrees,
    'eyepieces': value.eyepieces.map((item) => item.toMap()).toList(),
  };
  return jsonEncode(signature(before)) != jsonEncode(signature(after));
}
