import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Removes credential entries used by pre-auto-configuration builds.
///
/// Production services do not read provider credentials from this service.
/// The class remains injectable only to make upgrades clean up obsolete values
/// without a database migration.
class ApiKeyService {
  ApiKeyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _legacyKeys = <String>[
    'secure_api_google_maps',
    'secure_api_weather',
    'secure_astronomy_app_id',
    'secure_astronomy_app_secret',
    'secure_api_astrometry_net',
  ];

  final FlutterSecureStorage _storage;

  Future<void> clearLegacyCredentials() async {
    try {
      for (final key in _legacyKeys) {
        await _storage.delete(key: key);
      }
    } on MissingPluginException {
      // Unit tests and unsupported platforms have no secure-storage plugin.
    } on PlatformException {
      // Credential cleanup must never prevent application startup.
    }
  }
}
