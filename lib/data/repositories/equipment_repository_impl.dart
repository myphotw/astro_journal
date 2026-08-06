import '../datasources/equipment_local_datasource.dart';
import '../models/equipment.dart';
import 'equipment_repository.dart';

class EquipmentRepositoryImpl implements EquipmentRepository {
  EquipmentRepositoryImpl({EquipmentLocalDataSource? dataSource})
      : _dataSource = dataSource ?? EquipmentLocalDataSource();

  final EquipmentLocalDataSource _dataSource;

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) =>
      _dataSource.getAll(activeOnly: activeOnly);

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
  }

  @override
  Future<void> delete(String id) => _dataSource.delete(id);
}
