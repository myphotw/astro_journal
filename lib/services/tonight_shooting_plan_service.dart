import 'package:shared_preferences/shared_preferences.dart';

/// 오늘 밤 촬영 계획(순서 있는 천체 ID 목록)을 날짜별로 저장한다.
class TonightShootingPlanSnapshot {
  const TonightShootingPlanSnapshot({
    required this.orderedObjectIds,
    this.userEdited = false,
  });

  final List<String> orderedObjectIds;
  final bool userEdited;

  bool get isEmpty => orderedObjectIds.isEmpty;
}

class TonightShootingPlanService {
  static const _orderKeyPrefix = 'tonight_shooting_plan_order_v2_';
  static const _userEditedKeyPrefix = 'tonight_shooting_plan_user_edited_v2_';

  String _orderKeyForDate(DateTime planDate) =>
      '$_orderKeyPrefix${_dateKey(planDate)}';

  String _userEditedKeyForDate(DateTime planDate) =>
      '$_userEditedKeyPrefix${_dateKey(planDate)}';

  String _dateKey(DateTime planDate) {
    final local = planDate.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<TonightShootingPlanSnapshot> loadSnapshotForDate(
    DateTime planDate,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final orderKey = _orderKeyForDate(planDate);
    final editedKey = _userEditedKeyForDate(planDate);

    final storedOrder = prefs.getStringList(orderKey);
    if (storedOrder != null) {
      return TonightShootingPlanSnapshot(
        orderedObjectIds: List<String>.from(storedOrder),
        userEdited: prefs.getBool(editedKey) ?? false,
      );
    }

    return const TonightShootingPlanSnapshot(orderedObjectIds: []);
  }

  Future<void> saveSnapshotForDate(
    DateTime planDate,
    TonightShootingPlanSnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final orderKey = _orderKeyForDate(planDate);
    final editedKey = _userEditedKeyForDate(planDate);

    if (snapshot.orderedObjectIds.isEmpty) {
      await prefs.remove(orderKey);
      await prefs.remove(editedKey);
      return;
    }

    await prefs.setStringList(orderKey, snapshot.orderedObjectIds);
    await prefs.setBool(editedKey, snapshot.userEdited);
  }

  Future<void> add(DateTime planDate, String objectId) async {
    final current = await loadSnapshotForDate(planDate);
    if (current.orderedObjectIds.contains(objectId)) {
      return;
    }
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: [...current.orderedObjectIds, objectId],
        userEdited: true,
      ),
    );
  }

  Future<void> remove(DateTime planDate, String objectId) async {
    final current = await loadSnapshotForDate(planDate);
    final next = current.orderedObjectIds.where((id) => id != objectId).toList();
    if (next.length == current.orderedObjectIds.length) {
      return;
    }
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: next,
        userEdited: true,
      ),
    );
  }

  Future<void> saveOrderedForDate(
    DateTime planDate,
    List<String> orderedObjectIds, {
    required bool userEdited,
  }) async {
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: orderedObjectIds,
        userEdited: userEdited,
      ),
    );
  }
}
