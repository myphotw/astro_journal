import 'dart:async';

import '../data/models/tc_backend_models.dart';
import 'tc_backend_connection_manager.dart';
import 'tc_backend_sync_coordinator.dart';

enum GalleryRefreshResult { updated, recent, offline }

/// Coordinates startup, foreground, and gallery refreshes around one cursor pull.
class GalleryIncrementalRefreshService implements TcBackendDrainRunner {
  GalleryIncrementalRefreshService({
    required this.pull,
    required this.connection,
    DateTime Function()? now,
    this.minimumInterval = const Duration(seconds: 30),
    this.manualInterval = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  final TcBackendDrainRunner pull;
  final TcBackendConnectionManager connection;
  final DateTime Function() _now;
  final Duration minimumInterval;
  final Duration manualInterval;
  Future<GalleryRefreshResult>? _active;
  DateTime? _lastSuccess;

  Future<GalleryRefreshResult> refresh({bool force = false}) {
    final active = _active;
    if (active != null) return active;
    if (connection.status != TcBackendConnectionStatus.connected &&
        connection.status != TcBackendConnectionStatus.degraded) {
      return Future.value(GalleryRefreshResult.offline);
    }
    final lastSuccess = _lastSuccess;
    if (lastSuccess != null &&
        _now().difference(lastSuccess) <
            (force ? manualInterval : minimumInterval)) {
      return Future.value(GalleryRefreshResult.recent);
    }
    return _startPull();
  }

  Future<GalleryRefreshResult> _startPull() {
    final pending = _refreshOnce();
    _active = pending;
    pending.whenComplete(() => _active = null).ignore();
    return pending;
  }

  Future<GalleryRefreshResult> _refreshOnce() async {
    await pull.drain();
    _lastSuccess = _now();
    return GalleryRefreshResult.updated;
  }

  @override
  Future<void> drain() async {
    // Startup already checks backend settings; preserve its existing pull path
    // even while the connection manager is still probing an endpoint.
    await (_active ?? _startPull());
  }
}
