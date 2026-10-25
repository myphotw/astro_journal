import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/tc_backend_models.dart';
import 'tc_backend_auth_service.dart';
import 'tc_backend_service.dart';
import 'tc_backend_settings_service.dart';

typedef TcBackendServiceFactory =
    TcBackendService Function(String baseUrl, Duration timeout);

class TcBackendConnectionManager extends ChangeNotifier {
  TcBackendConnectionManager({
    required TcBackendSettingsService settingsService,
    required TcBackendAuthHeaders authHeaders,
    required Stream<void> networkChanges,
    TcBackendServiceFactory? serviceFactory,
    Duration networkChangeDebounce = const Duration(milliseconds: 500),
    Duration internalProbeTimeout = const Duration(seconds: 1),
    Duration externalProbeTimeout = const Duration(seconds: 2),
    Duration fallbackProbeTimeout = const Duration(seconds: 4),
  }) : this._(
         settingsService,
         networkChanges,
         serviceFactory ??
             ((baseUrl, timeout) => TcBackendService(
               baseUrl: baseUrl,
               timeout: timeout,
               authHeaders: authHeaders,
             )),
         networkChangeDebounce,
         internalProbeTimeout,
         externalProbeTimeout,
         fallbackProbeTimeout,
       );

  TcBackendConnectionManager._(
    this._settingsService,
    this._networkChanges,
    this._serviceFactory,
    this.networkChangeDebounce,
    this.internalProbeTimeout,
    this.externalProbeTimeout,
    this.fallbackProbeTimeout,
  );

  final TcBackendSettingsService _settingsService;
  final Stream<void> _networkChanges;
  final TcBackendServiceFactory _serviceFactory;
  final Duration networkChangeDebounce;
  final Duration internalProbeTimeout;
  final Duration externalProbeTimeout;
  final Duration fallbackProbeTimeout;

  StreamSubscription<void>? _networkSubscription;
  Timer? _networkDebounceTimer;
  Future<void>? _activeReconnect;
  bool _reconnectRequested = false;
  bool _disposed = false;

  TcBackendConnectionStatus _status = TcBackendConnectionStatus.notConfigured;
  TcBackendConnectionStatus get status => _status;

  TcBackendCheckResult? _result;
  TcBackendCheckResult? get result => _result;

  TcBackendEndpoint? _selectedEndpoint;
  TcBackendEndpoint? get selectedEndpoint => _selectedEndpoint;

  TcBackendEndpoint? _lastCheckedEndpoint;
  TcBackendEndpoint? get lastCheckedEndpoint => _lastCheckedEndpoint;

  DateTime? _lastCheckedAt;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  bool get isChecking => _status == TcBackendConnectionStatus.checking;

  void start() {
    if (_disposed || _networkSubscription != null) return;
    _networkSubscription = _networkChanges.listen(
      (_) => _scheduleNetworkReconnect(),
      onError: (_) => _scheduleNetworkReconnect(),
    );
    unawaited(reconnect());
  }

  Future<void> pause() async {
    _networkDebounceTimer?.cancel();
    _networkDebounceTimer = null;
    await _networkSubscription?.cancel();
    _networkSubscription = null;
  }

  void resume() {
    if (_disposed) return;
    if (_networkSubscription == null) {
      start();
    } else {
      unawaited(reconnect());
    }
  }

  Future<void> reconnect() {
    return _requestReconnect(queueIfActive: false);
  }

  Future<void> _requestReconnect({required bool queueIfActive}) {
    if (_disposed) return Future.value();
    final active = _activeReconnect;
    if (active != null) {
      if (queueIfActive) _reconnectRequested = true;
      return active;
    }

    _reconnectRequested = true;
    final run = _drainReconnectRequests();
    _activeReconnect = run;
    return run.whenComplete(() {
      if (identical(_activeReconnect, run)) _activeReconnect = null;
    });
  }

  Future<void> _drainReconnectRequests() async {
    while (_reconnectRequested && !_disposed) {
      _reconnectRequested = false;
      await _checkEndpoints();
    }
  }

  Future<void> _checkEndpoints() async {
    final endpoints = await _settingsService.endpoints();
    if (_disposed) return;
    if (endpoints.isEmpty) {
      _status = TcBackendConnectionStatus.notConfigured;
      _result = const TcBackendCheckResult(
        status: TcBackendConnectionStatus.notConfigured,
        message: '구성된 TC-Backend 주소가 없습니다.',
      );
      _lastCheckedAt = DateTime.now();
      notifyListeners();
      return;
    }

    _status = TcBackendConnectionStatus.checking;
    _result = null;
    notifyListeners();

    TcBackendCheckResult? lastResult;
    TcBackendEndpoint? lastEndpoint;
    for (final endpoint in endpoints) {
      if (_disposed) return;
      lastEndpoint = endpoint;
      late TcBackendCheckResult result;
      try {
        result = await _serviceFactory(
          endpoint.baseUrl,
          _probeTimeout(endpoint.kind),
        ).checkCompatibility();
      } on Object {
        result = const TcBackendCheckResult(
          status: TcBackendConnectionStatus.serverError,
          message: '서버 연결 검사 중 오류가 발생했습니다.',
        );
      }
      if (_disposed) return;
      lastResult = result;
      if (_usesEndpoint(result.status)) {
        _settingsService.selectEndpoint(endpoint);
        _selectedEndpoint = endpoint;
        _lastCheckedEndpoint = endpoint;
        _result = result;
        _status = result.status;
        _lastCheckedAt = DateTime.now();
        notifyListeners();
        return;
      }
    }

    _lastCheckedEndpoint = lastEndpoint;
    _result = lastResult;
    _status = lastResult?.status ?? TcBackendConnectionStatus.unreachable;
    _lastCheckedAt = DateTime.now();
    notifyListeners();
  }

  bool _usesEndpoint(TcBackendConnectionStatus status) => switch (status) {
    TcBackendConnectionStatus.connected ||
    TcBackendConnectionStatus.degraded ||
    TcBackendConnectionStatus.incompatible ||
    TcBackendConnectionStatus.authenticationFailed ||
    TcBackendConnectionStatus.serverError => true,
    _ => false,
  };

  Duration _probeTimeout(TcBackendEndpointKind kind) => switch (kind) {
    TcBackendEndpointKind.internal => internalProbeTimeout,
    TcBackendEndpointKind.external => externalProbeTimeout,
    TcBackendEndpointKind.legacy ||
    TcBackendEndpointKind.custom => fallbackProbeTimeout,
  };

  void _scheduleNetworkReconnect() {
    if (_disposed) return;
    _networkDebounceTimer?.cancel();
    _networkDebounceTimer = Timer(networkChangeDebounce, () {
      _networkDebounceTimer = null;
      unawaited(_requestReconnect(queueIfActive: true));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _networkDebounceTimer?.cancel();
    unawaited(_networkSubscription?.cancel());
    _networkSubscription = null;
    super.dispose();
  }
}
