import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'google_maps_native_key_service.dart';

/// All API credential types persisted in the device secure storage.
enum ApiKeyType {
  googleMaps,
  weather,
  astronomyAppId,
  astronomyAppSecret,
  astrometryNet;

  String get storageKey {
    switch (this) {
      case ApiKeyType.googleMaps:
        return 'secure_api_google_maps';
      case ApiKeyType.weather:
        return 'secure_api_weather';
      case ApiKeyType.astronomyAppId:
        return 'secure_astronomy_app_id';
      case ApiKeyType.astronomyAppSecret:
        return 'secure_astronomy_app_secret';
      case ApiKeyType.astrometryNet:
        return 'secure_api_astrometry_net';
    }
  }

  String get label {
    switch (this) {
      case ApiKeyType.googleMaps:
        return 'Google Maps API Key';
      case ApiKeyType.weather:
        return 'Weather API Key';
      case ApiKeyType.astronomyAppId:
        return 'Astronomy Application ID';
      case ApiKeyType.astronomyAppSecret:
        return 'Astronomy Application Secret';
      case ApiKeyType.astrometryNet:
        return 'Astrometry.net API Key';
    }
  }

  bool get isSecret =>
      this == ApiKeyType.astronomyAppSecret || this == ApiKeyType.astrometryNet;
}

/// Service for securely storing and retrieving API credentials.
///
/// Google Maps key is the single source of truth for Geocoding / Static Map
/// HTTP calls and for the native GoogleMap SDK ([GoogleMapsNativeKeyService]).
class ApiKeyService {
  final _storage = const FlutterSecureStorage();

  Future<String?> get(ApiKeyType type) =>
      _storage.read(key: type.storageKey);

  Future<Map<ApiKeyType, String?>> getAll() async {
    final map = <ApiKeyType, String?>{};
    for (final type in ApiKeyType.values) {
      map[type] = await _storage.read(key: type.storageKey);
    }
    return map;
  }

  Future<void> save(ApiKeyType type, String value) async {
    final trimmed = value.trim();
    await _storage.write(key: type.storageKey, value: trimmed);
    if (type == ApiKeyType.googleMaps) {
      await GoogleMapsNativeKeyService.syncKey(trimmed);
    }
  }

  Future<void> delete(ApiKeyType type) async {
    await _storage.delete(key: type.storageKey);
    if (type == ApiKeyType.googleMaps) {
      await GoogleMapsNativeKeyService.syncKey(null);
    }
  }

  Future<bool> has(ApiKeyType type) async {
    final value = await _storage.read(key: type.storageKey);
    return value != null && value.isNotEmpty;
  }

  Future<void> syncGoogleMapsKeyToNative() async {
    final key = await get(ApiKeyType.googleMaps);
    await GoogleMapsNativeKeyService.syncKey(key, force: true);
  }

  /// Seeds SecureStorage from the build-time Manifest key when Settings is empty.
  Future<void> ensureGoogleMapsKeyFromNative() async {
    if (await has(ApiKeyType.googleMaps)) {
      await syncGoogleMapsKeyToNative();
      return;
    }

    final manifestKey = await GoogleMapsNativeKeyService.getManifestApiKey();
    if (manifestKey != null && manifestKey.isNotEmpty) {
      await save(ApiKeyType.googleMaps, manifestKey);
      return;
    }

    await syncGoogleMapsKeyToNative();
  }
}
