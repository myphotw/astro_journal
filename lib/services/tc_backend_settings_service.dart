import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_build_config.dart';

enum TcBackendEndpointKind { internal, external, legacy, custom }

class TcBackendEndpoint {
  const TcBackendEndpoint({required this.baseUrl, required this.kind});

  final String baseUrl;
  final TcBackendEndpointKind kind;
}

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
  TcBackendSettingsService({
    this.useBuildConfiguration = false,
    this.buildBaseUrl = AppBuildConfig.backendUrl,
    this.buildInternalUrl = AppBuildConfig.backendUrlInternal,
    this.buildExternalUrl = AppBuildConfig.backendUrlExternal,
  });

  /// Production factory. Runtime preferences are deliberately ignored so a
  /// reinstall or a stale V1 preference cannot redirect the application.
  factory TcBackendSettingsService.autoConfigured() =>
      TcBackendSettingsService(useBuildConfiguration: true);

  static const _baseUrlKey = 'tc_backend_base_url';
  static const _enabledKey = 'tc_backend_enabled';

  final bool useBuildConfiguration;
  final String buildBaseUrl;
  final String buildInternalUrl;
  final String buildExternalUrl;
  String? _selectedBuildBaseUrl;

  List<TcBackendEndpoint> get configuredEndpoints {
    if (!useBuildConfiguration) return const [];
    final endpoints = <TcBackendEndpoint>[];
    final seen = <String>{};
    void add(String value, TcBackendEndpointKind kind) {
      final normalized = TcBackendSettings.normalizeBaseUrl(value);
      if (normalized != null && seen.add(normalized)) {
        endpoints.add(TcBackendEndpoint(baseUrl: normalized, kind: kind));
      }
    }

    add(buildInternalUrl, TcBackendEndpointKind.internal);
    add(buildExternalUrl, TcBackendEndpointKind.external);
    add(buildBaseUrl, TcBackendEndpointKind.legacy);
    return List.unmodifiable(endpoints);
  }

  Future<List<TcBackendEndpoint>> endpoints() async {
    if (useBuildConfiguration) return configuredEndpoints;
    final settings = await load();
    final normalized = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    return normalized == null
        ? const []
        : [
            TcBackendEndpoint(
              baseUrl: normalized,
              kind: TcBackendEndpointKind.custom,
            ),
          ];
  }

  void selectEndpoint(TcBackendEndpoint endpoint) {
    if (!useBuildConfiguration) return;
    final allowed = configuredEndpoints.any(
      (candidate) => candidate.baseUrl == endpoint.baseUrl,
    );
    if (!allowed) {
      throw ArgumentError.value(
        endpoint.baseUrl,
        'endpoint',
        'Endpoint is not part of the build configuration.',
      );
    }
    _selectedBuildBaseUrl = endpoint.baseUrl;
  }

  Future<TcBackendSettings> load() async {
    if (useBuildConfiguration) {
      final endpoints = configuredEndpoints;
      final normalized =
          _selectedBuildBaseUrl ??
          (endpoints.isEmpty ? null : endpoints.first.baseUrl);
      return TcBackendSettings(
        baseUrl: normalized ?? AppBuildConfig.defaultBackendUrl,
        enabled: true,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    return TcBackendSettings(
      baseUrl: prefs.getString(_baseUrlKey) ?? '',
      enabled: prefs.getBool(_enabledKey) ?? false,
    );
  }

  Future<void> save(TcBackendSettings settings) async {
    if (useBuildConfiguration) return;
    final normalized = TcBackendSettings.normalizeBaseUrl(settings.baseUrl);
    if (settings.enabled && normalized == null) {
      throw const FormatException('유효한 TC-Backend 주소를 입력하세요.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized ?? settings.baseUrl.trim());
    await prefs.setBool(_enabledKey, settings.enabled);
  }
}
