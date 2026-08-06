import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/equipment_kind.dart';
import '../../../core/constants/equipment_purpose.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/eyepiece.dart';
import '../../../data/repositories/equipment_repository.dart';

class EquipmentViewModel extends ChangeNotifier {
  EquipmentViewModel(this._repository);

  final EquipmentRepository _repository;

  bool _isLoading = false;
  String? _errorMessage;
  List<Equipment> _equipment = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Equipment> get equipment => List.unmodifiable(_equipment);

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _equipment = await _repository.getAll();
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> save(Equipment equipment) async {
    _errorMessage = null;
    try {
      await _repository.save(equipment);
      await load();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> delete(String id) async {
    _errorMessage = null;
    try {
      await _repository.delete(id);
      await load();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleActive(Equipment item) async {
    return save(item.copyWith(isActive: !item.isActive));
  }

  Equipment newEquipment({
    EquipmentPurpose purpose = EquipmentPurpose.imaging,
  }) {
    return Equipment(
      id: const Uuid().v4(),
      name: '',
      kind: EquipmentKind.smartTelescope,
      purpose: purpose,
      isActive: true,
      sortOrder: _equipment.length,
    );
  }

  Eyepiece newEyepiece(String equipmentId) {
    return Eyepiece(
      id: const Uuid().v4(),
      equipmentId: equipmentId,
      name: '',
      focalLengthMm: 0,
      afovDegrees: 0,
    );
  }
}
