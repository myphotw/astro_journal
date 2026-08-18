import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import 'tc_backend_settings_service.dart';

abstract class TcBackendTokenStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> deleteToken();
}

/// Stores the TC-Backend client credential outside SharedPreferences/SQLite.
class TcBackendAuthService implements TcBackendTokenStore {
  TcBackendAuthService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'tc_backend_auth_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() async {
    try {
      final value = (await _storage.read(key: storageKey))?.trim();
      return value == null || value.isEmpty ? null : value;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> saveToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      await deleteToken();
      return;
    }
    await _storage.write(key: storageKey, value: value);
  }

  @override
  Future<void> deleteToken() => _storage.delete(key: storageKey);

  Future<bool> hasToken() async => await readToken() != null;
}

/// Produces request headers without exposing the credential to callers.
class TcBackendAuthHeaders {
  TcBackendAuthHeaders(TcBackendTokenStore tokenStore)
    : _tokenStore = tokenStore;

  final TcBackendTokenStore _tokenStore;

  Future<Map<String, String>> build({bool json = false}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json';
    final token = await _tokenStore.readToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }
}

class EmptyTcBackendTokenStore implements TcBackendTokenStore {
  const EmptyTcBackendTokenStore();

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> deleteToken() async {}
}

/// Supplies credentials only for protected media hosted by the configured
/// TC-Backend origin. Tokens are never appended to URLs.
class TcBackendMediaAuthService {
  TcBackendMediaAuthService(this._settingsService, this._authHeaders);

  final TcBackendSettingsService _settingsService;
  final TcBackendAuthHeaders _authHeaders;

  Future<TcBackendMediaRequest> requestFor(String url) async {
    final parsed = Uri.tryParse(url);
    final settings = await _settingsService.load();
    final base = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (!settings.enabled || base == null || parsed == null) {
      return TcBackendMediaRequest(url: url);
    }
    final baseUri = Uri.parse(base);
    final mediaUri = parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
    final sameOrigin =
        mediaUri.scheme == baseUri.scheme &&
        mediaUri.host == baseUri.host &&
        mediaUri.port == baseUri.port;
    if (!sameOrigin || !mediaUri.path.startsWith('/api/')) {
      return TcBackendMediaRequest(url: url);
    }
    return TcBackendMediaRequest(
      url: mediaUri.toString(),
      headers: await _authHeaders.build(),
    );
  }

  Future<Map<String, String>> headersFor(String url) async =>
      (await requestFor(url)).headers;
}

class TcBackendMediaRequest {
  const TcBackendMediaRequest({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}
