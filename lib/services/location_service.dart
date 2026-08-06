import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'app_logger.dart';

/// Abstraction over the device GPS.
///
/// All API calls in this app use [LocationData.latitude] and
/// [LocationData.longitude] rather than city names.
class LocationService {
  static const _tag = 'LocationService';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether the device's location service (GPS/network) is switched on.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Checks the current permission state without prompting the user.
  Future<LocationPermissionStatus> checkPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return LocationPermissionStatus.serviceDisabled;
    final perm = await Geolocator.checkPermission();
    return _map(perm);
  }

  /// Requests permission if not yet granted.
  ///
  /// Returns the resulting [LocationPermissionStatus].
  Future<LocationPermissionStatus> requestPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return LocationPermissionStatus.serviceDisabled;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    AppLogger.info(_tag, 'Permission: $perm');
    return _map(perm);
  }

  /// Returns the current [LocationData].
  ///
  /// Automatically requests permission if needed.
  /// Throws [Exception] if permission is denied or service is disabled.
  ///
  /// [preferLastKnown]가 true이면 캐시된 마지막 위치를 우선 사용해
  /// GPS 고정 대기로 화면이 멈추는 것을 줄인다. 최신 위치가 필요하면
  /// [timeLimit] 안에서 재획득을 시도한다.
  Future<LocationData> getCurrentLocation({
    bool preferLastKnown = false,
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    final status = await requestPermission();

    switch (status) {
      case LocationPermissionStatus.serviceDisabled:
        throw Exception('위치 서비스가 비활성화되어 있습니다. 기기 설정에서 위치를 켜주세요.');
      case LocationPermissionStatus.deniedForever:
        throw Exception('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 위치 권한을 허용해 주세요.');
      case LocationPermissionStatus.deniedOnce:
        throw Exception('위치 권한이 거부되었습니다.');
      case LocationPermissionStatus.granted:
        break;
    }

    if (preferLastKnown) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        AppLogger.info(
          _tag,
          'LastKnown: ${last.latitude}, ${last.longitude}',
        );
        // 백그라운드에서 최신 위치 갱신을 시도하되 UI는 막지 않는다.
        unawaited(_refreshCurrentPosition(timeLimit: timeLimit));
        return LocationData(
          latitude: last.latitude,
          longitude: last.longitude,
          accuracy: last.accuracy,
          timestamp: last.timestamp,
        );
      }
    }

    final position = await _getCurrentPosition(timeLimit: timeLimit);

    AppLogger.info(
      _tag,
      'Position: ${position.latitude}, ${position.longitude} (±${position.accuracy.toStringAsFixed(1)}m)',
    );

    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp,
    );
  }

  Future<Position> _getCurrentPosition({required Duration timeLimit}) {
    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: timeLimit,
      ),
    );
  }

  Future<void> _refreshCurrentPosition({required Duration timeLimit}) async {
    try {
      await _getCurrentPosition(timeLimit: timeLimit);
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  LocationPermissionStatus _map(LocationPermission perm) {
    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.deniedOnce;
    }
  }
}

// ── Value objects ───────────────────────────────────────────────────────────

enum LocationPermissionStatus {
  granted,
  deniedOnce,
  deniedForever,
  serviceDisabled;

  String get label {
    switch (this) {
      case granted:
        return '허용됨';
      case deniedOnce:
        return '거부됨';
      case deniedForever:
        return '영구 거부';
      case serviceDisabled:
        return '위치 서비스 꺼짐';
    }
  }
}

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres.
  final double accuracy;
  final DateTime timestamp;
}
