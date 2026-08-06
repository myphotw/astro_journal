import 'package:flutter/foundation.dart';

import '../../../data/models/tc_backend_models.dart';
import '../../../services/tc_backend_service.dart';
import '../../../services/tc_backend_settings_service.dart';

class TcBackendViewModel extends ChangeNotifier {
  TcBackendViewModel(this._settingsService, {this.serviceFactory});

  final TcBackendSettingsService _settingsService;
  final TcBackendService Function(String baseUrl)? serviceFactory;

  TcBackendSettings _settings = const TcBackendSettings(
    baseUrl: '',
    enabled: false,
  );
  TcBackendSettings get settings => _settings;

  TcBackendCheckResult? _result;
  TcBackendCheckResult? get result => _result;

  TcBackendConnectionStatus _status = TcBackendConnectionStatus.notConfigured;
  TcBackendConnectionStatus get status => _status;

  Future<void> load() async {
    _settings = await _settingsService.load();
    _status = _settings.enabled && _settings.isConfigured
        ? TcBackendConnectionStatus.notConfigured
        : TcBackendConnectionStatus.notConfigured;
    notifyListeners();
  }

  Future<void> save({required String baseUrl, required bool enabled}) async {
    final settings = TcBackendSettings(baseUrl: baseUrl, enabled: enabled);
    await _settingsService.save(settings);
    _settings = await _settingsService.load();
    _result = null;
    _status = TcBackendConnectionStatus.notConfigured;
    notifyListeners();
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
