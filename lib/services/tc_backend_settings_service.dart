import 'package:shared_preferences/shared_preferences.dart';

class TcBackendSettings {
  const TcBackendSettings({required this.baseUrl, required this.enabled});

  final String baseUrl;
  final bool enabled;

  bool get isConfigured => normalizeBaseUrl(baseUrl) != null;

  static String? normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    final path = uri.path == '/'
        ? ''
        : uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isNotEmpty) return null;
    return uri
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}

class TcBackendSettingsService {
  static const _baseUrlKey = 'tc_backend_base_url';
  static const _enabledKey = 'tc_backend_enabled';

  Future<TcBackendSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TcBackendSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      enabled: prefs.getBool(_enabledKey) ?? false,
    );
  }

  Future<void> save(TcBackendSettings settings) async {
    final normalized = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (settings.enabled && normalized == null) {
      throw const FormatException('유효한 TC-Backend 주소를 입력하세요.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized ?? settings.baseUrl.trim());
    await prefs.setBool(_enabledKey, settings.enabled);
  }
}
