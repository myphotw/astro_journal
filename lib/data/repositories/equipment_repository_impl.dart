import '../../core/services/observation_context_invalidator.dart';
import '../../core/services/performance_probe.dart';
import '../datasources/equipment_local_datasource.dart';
import '../models/equipment.dart';
import 'equipment_repository.dart';

class EquipmentRepositoryImpl implements EquipmentRepository {
  EquipmentRepositoryImpl({
    EquipmentLocalDataSource? dataSource,
    this.contextInvalidator,
  }) : _dataSource = dataSource ?? EquipmentLocalDataSource();

  final EquipmentLocalDataSource _dataSource;
  final ObservationContextInvalidator? contextInvalidator;

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
    await contextInvalidator?.invalidate(ObservationContextChange.equipment);
  }

  @override
  Future<void> delete(String id) async {
    await _dataSource.delete(id);
    await contextInvalidator?.invalidate(ObservationContextChange.equipment);
  }
}
