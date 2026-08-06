import '../models/equipment.dart';

abstract class EquipmentRepository {
  Future<List<Equipment>> getAll({bool activeOnly = false});
  Future<Equipment?> getById(String id);
  Future<void> save(Equipment equipment);
  Future<void> delete(String id);
}
