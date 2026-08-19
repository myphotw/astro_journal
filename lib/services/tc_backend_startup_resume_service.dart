import 'package:flutter/foundation.dart';

import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';

/// Starts durable sync without making startup wait for network work.
class TcBackendStartupResumeService {
  factory TcBackendStartupResumeService(
    TcBackendSettingsService settings,
    TcBackendDrainRunner coordinator, {
    Future<void> Function()? reconcileCatalog,
  }) =>
      TcBackendStartupResumeService._(settings, coordinator, reconcileCatalog);

  TcBackendStartupResumeService._(
    this._settings,
    this._coordinator,
    this._reconcileCatalog,
  );

  final TcBackendSettingsService _settings;
  final TcBackendDrainRunner _coordinator;
  final Future<void> Function()? _reconcileCatalog;

  Future<void> resume() async {
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _coordinator.drain();
    } catch (error) {
      debugPrint('TC-Backend startup resume skipped: $error');
    } finally {
      try {
        await _reconcileCatalog?.call();
      } catch (error) {
        debugPrint('Catalog capture startup reconciliation skipped: $error');
      }
    }
  }
}
