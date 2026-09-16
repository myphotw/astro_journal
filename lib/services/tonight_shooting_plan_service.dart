import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum TonightPlanSource { automatic, manual }

class TonightShootingPlanEntry {
  const TonightShootingPlanEntry({
    required this.objectId,
    this.startTime,
    this.endTime,
    this.source = TonightPlanSource.automatic,
    this.hasTimeOverride = false,
  });

  final String objectId;
  final DateTime? startTime;
  final DateTime? endTime;
  final TonightPlanSource source;
  final bool hasTimeOverride;

  bool get hasValidTime =>
      startTime != null && endTime != null && endTime!.isAfter(startTime!);

  TonightShootingPlanEntry copyWith({
    DateTime? startTime,
    DateTime? endTime,
    TonightPlanSource? source,
    bool? hasTimeOverride,
    bool clearTime = false,
  }) => TonightShootingPlanEntry(
    objectId: objectId,
    startTime: clearTime ? null : (startTime ?? this.startTime),
    endTime: clearTime ? null : (endTime ?? this.endTime),
    source: source ?? this.source,
    hasTimeOverride: hasTimeOverride ?? this.hasTimeOverride,
  );

  Map<String, Object?> toJson() => {
    'object_id': objectId,
    'start_time': startTime?.toIso8601String(),
    'end_time': endTime?.toIso8601String(),
    'source': source.name,
    'has_time_override': hasTimeOverride,
  };

  factory TonightShootingPlanEntry.fromJson(Map<String, dynamic> json) {
    final objectId = json['object_id'];
    if (objectId is! String || objectId.isEmpty) {
      throw const FormatException('Tonight plan object_id is missing.');
    }
    return TonightShootingPlanEntry(
      objectId: objectId,
      startTime: _date(json['start_time']),
      endTime: _date(json['end_time']),
      source: TonightPlanSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => TonightPlanSource.automatic,
      ),
      hasTimeOverride: json['has_time_override'] == true,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// 오늘 밤 촬영 계획을 날짜별로 저장한다.
class TonightShootingPlanSnapshot {
  const TonightShootingPlanSnapshot({
    required this.orderedObjectIds,
    this.userEdited = false,
    this.entries = const [],
  });

  final List<String> orderedObjectIds;
  final bool userEdited;
  final List<TonightShootingPlanEntry> entries;

  bool get isEmpty => orderedObjectIds.isEmpty;

  TonightShootingPlanEntry? entryFor(String objectId) {
    for (final entry in entries) {
      if (entry.objectId == objectId) return entry;
    }
    return null;
  }
}

class TonightShootingPlanService {
  static const _orderKeyPrefix = 'tonight_shooting_plan_order_v2_';
  static const _userEditedKeyPrefix = 'tonight_shooting_plan_user_edited_v2_';
  static const _entriesKeyPrefix = 'tonight_shooting_plan_entries_v3_';

  String _orderKeyForDate(DateTime planDate) =>
      '$_orderKeyPrefix${_dateKey(planDate)}';

  String _userEditedKeyForDate(DateTime planDate) =>
      '$_userEditedKeyPrefix${_dateKey(planDate)}';

  String _entriesKeyForDate(DateTime planDate) =>
      '$_entriesKeyPrefix${_dateKey(planDate)}';

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
    final storedOrder = prefs.getStringList(_orderKeyForDate(planDate));
    final entries = _decodeEntries(
      prefs.getString(_entriesKeyForDate(planDate)),
    );
    if (storedOrder != null || entries.isNotEmpty) {
      final orderedIds =
          storedOrder ??
          entries.map((entry) => entry.objectId).toList(growable: false);
      return TonightShootingPlanSnapshot(
        orderedObjectIds: List<String>.from(orderedIds),
        userEdited: prefs.getBool(_userEditedKeyForDate(planDate)) ?? false,
        entries: _orderedEntries(orderedIds, entries),
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
    final entriesKey = _entriesKeyForDate(planDate);

    if (snapshot.orderedObjectIds.isEmpty) {
      await prefs.remove(orderKey);
      await prefs.remove(editedKey);
      await prefs.remove(entriesKey);
      return;
    }

    await prefs.setStringList(orderKey, snapshot.orderedObjectIds);
    await prefs.setBool(editedKey, snapshot.userEdited);
    if (snapshot.entries.isEmpty) {
      await prefs.remove(entriesKey);
    } else {
      await prefs.setString(
        entriesKey,
        jsonEncode(snapshot.entries.map((entry) => entry.toJson()).toList()),
      );
    }
  }

  Future<void> add(DateTime planDate, String objectId) async {
    final current = await loadSnapshotForDate(planDate);
    if (current.orderedObjectIds.contains(objectId)) return;
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: [...current.orderedObjectIds, objectId],
        userEdited: true,
        entries: [
          ...current.entries,
          TonightShootingPlanEntry(objectId: objectId),
        ],
      ),
    );
  }

  Future<void> remove(DateTime planDate, String objectId) async {
    final current = await loadSnapshotForDate(planDate);
    final next = current.orderedObjectIds
        .where((id) => id != objectId)
        .toList();
    if (next.length == current.orderedObjectIds.length) return;
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: next,
        userEdited: true,
        entries: current.entries
            .where((entry) => entry.objectId != objectId)
            .toList(),
      ),
    );
  }

  Future<void> saveOrderedForDate(
    DateTime planDate,
    List<String> orderedObjectIds, {
    required bool userEdited,
  }) async {
    final current = await loadSnapshotForDate(planDate);
    await saveSnapshotForDate(
      planDate,
      TonightShootingPlanSnapshot(
        orderedObjectIds: orderedObjectIds,
        userEdited: userEdited,
        entries: _orderedEntries(orderedObjectIds, current.entries),
      ),
    );
  }

  List<TonightShootingPlanEntry> _decodeEntries(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (json) => TonightShootingPlanEntry.fromJson(
              Map<String, dynamic>.from(json),
            ),
          )
          .toList();
    } on FormatException {
      return const [];
    }
  }

  static List<TonightShootingPlanEntry> _orderedEntries(
    List<String> orderedIds,
    List<TonightShootingPlanEntry> entries,
  ) {
    final byId = {for (final entry in entries) entry.objectId: entry};
    return orderedIds
        .map((id) => byId[id] ?? TonightShootingPlanEntry(objectId: id))
        .toList();
  }
}
