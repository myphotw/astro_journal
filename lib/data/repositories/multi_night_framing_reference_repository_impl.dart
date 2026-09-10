import 'dart:async';

import 'package:flutter/foundation.dart';

import '../datasources/multi_night_framing_local_datasource.dart';
import '../models/multi_night_framing_reference.dart';
import 'multi_night_framing_reference_repository.dart';

class MultiNightFramingReferenceRepositoryImpl extends ChangeNotifier
    implements MultiNightFramingReferenceRepository {
  MultiNightFramingReferenceRepositoryImpl(this._local, {this.scheduleSync});

  final MultiNightFramingLocalDataSource _local;
  final Future<void> Function()? scheduleSync;

  @override
  Future<void> create(MultiNightFramingReference reference) async {
    await _local.create(reference);
    notifyListeners();
    _schedule();
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    notifyListeners();
    _schedule();
  }

  @override
  Future<MultiNightFramingReference?> find({
    required String catalogObjectId,
    required String equipmentId,
  }) => _local.findIdentity(
    catalogObjectId: catalogObjectId,
    equipmentId: equipmentId,
  );

  @override
  Future<MultiNightFramingReference?> get(String id) => _local.get(id);

  @override
  Future<List<MultiNightFramingReference>> list({
    String? catalogObjectId,
    String? equipmentId,
  }) => _local.list(catalogObjectId: catalogObjectId, equipmentId: equipmentId);

  @override
  Future<String?> latestConflictForCatalog(String catalogObjectId) =>
      _local.latestConflictForCatalog(catalogObjectId);

  @override
  Future<void> update(MultiNightFramingReference reference) async {
    await _local.update(reference);
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    final callback = scheduleSync;
    if (callback == null) return;
    unawaited(
      Future<void>.sync(callback).catchError((Object _, StackTrace __) {}),
    );
  }

  Future<void> notifyCanonicalChanged() async {
    notifyListeners();
  }
}
