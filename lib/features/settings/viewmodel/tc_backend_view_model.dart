import 'package:flutter/foundation.dart';

import '../../../data/models/tc_backend_models.dart';
import '../../../services/tc_backend_service.dart';
import '../../../services/tc_backend_settings_service.dart';
import '../../../data/repositories/sync_outbox_repository.dart';

class TcBackendSyncCounts {
  const TcBackendSyncCounts({
    this.queued = 0,
    this.processing = 0,
    this.failed = 0,
  });
  final int queued;
  final int processing;
  final int failed;
}

class TcBackendViewModel extends ChangeNotifier {
  TcBackendViewModel(
    this._settingsService, {
    this.serviceFactory,
    SyncOutboxRepository? syncOutboxRepository,
    Future<void> Function()? retryFailed,
  }) : _syncOutboxRepository = syncOutboxRepository,
       _retryFailed = retryFailed;

  final TcBackendSettingsService _settingsService;
  final TcBackendService Function(String baseUrl)? serviceFactory;
  final SyncOutboxRepository? _syncOutboxRepository;
  final Future<void> Function()? _retryFailed;

  TcBackendSettings _settings = const TcBackendSettings(
    baseUrl: '',
    enabled: false,
  );
  TcBackendSettings get settings => _settings;

  TcBackendCheckResult? _result;
  TcBackendCheckResult? get result => _result;

  TcBackendConnectionStatus _status = TcBackendConnectionStatus.notConfigured;
  TcBackendConnectionStatus get status => _status;

  TcBackendSyncCounts _syncCounts = const TcBackendSyncCounts();
  TcBackendSyncCounts get syncCounts => _syncCounts;
  bool get isBackendSyncAvailable =>
      _settings.enabled && _settings.isConfigured;

  Future<void> load() async {
    _settings = await _settingsService.load();
    _status = _settings.enabled && _settings.isConfigured
        ? TcBackendConnectionStatus.notConfigured
        : TcBackendConnectionStatus.notConfigured;
    await refreshSyncStatus(notify: false);
    notifyListeners();
  }

  Future<void> save({required String baseUrl, required bool enabled}) async {
    final settings = TcBackendSettings(baseUrl: baseUrl, enabled: enabled);
    await _settingsService.save(settings);
    _settings = await _settingsService.load();
    _result = null;
    _status = TcBackendConnectionStatus.notConfigured;
    await refreshSyncStatus(notify: false);
    notifyListeners();
  }

  Future<void> refreshSyncStatus({bool notify = true}) async {
    final repository = _syncOutboxRepository;
    if (!isBackendSyncAvailable || repository == null) {
      _syncCounts = const TcBackendSyncCounts();
    } else {
      final counts = await Future.wait([
        repository.countQueued(),
        repository.countProcessing(),
        repository.countFailed(),
      ]);
      _syncCounts = TcBackendSyncCounts(
        queued: counts[0],
        processing: counts[1],
        failed: counts[2],
      );
    }
    if (notify) notifyListeners();
  }

  Future<void> retryFailedSync() async {
    final retry = _retryFailed;
    if (retry == null || _syncCounts.failed == 0) return;
    await retry();
    await refreshSyncStatus();
  }

  Future<void> testConnection({
    required String baseUrl,
    required bool enabled,
  }) async {
    final normalized = TcBackendSettings.normalizeBaseUrl(baseUrl);
    if (!enabled || normalized == null) {
      _status = TcBackendConnectionStatus.notConfigured;
      _result = const TcBackendCheckResult(
        status: TcBackendConnectionStatus.notConfigured,
        message: 'TC-Backend를 켜고 유효한 서버 주소를 입력하세요.',
      );
      notifyListeners();
      return;
    }

    _status = TcBackendConnectionStatus.checking;
    _result = null;
    notifyListeners();
    final service =
        serviceFactory?.call(normalized) ??
        TcBackendService(baseUrl: normalized);
    _result = await service.checkCompatibility();
    _status = _result!.status;
    notifyListeners();
  }
}
