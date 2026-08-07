import 'package:flutter/foundation.dart';

import 'tc_backend_settings_service.dart';
import 'tc_backend_sync_coordinator.dart';

/// Starts durable sync without making startup wait for network work.
class TcBackendStartupResumeService {
  TcBackendStartupResumeService(this._settings, this._coordinator);

  final TcBackendSettingsService _settings;
  final TcBackendDrainRunner _coordinator;

  Future<void> resume() async {
    try {
      final settings = await _settings.load();
      if (!settings.enabled || !settings.isConfigured) return;
      await _coordinator.drain();
    } catch (error) {
      debugPrint('TC-Backend startup resume skipped: $error');
    }
  }
}
