import 'package:astro_journal/core/config/app_build_config.dart';
import 'package:astro_journal/services/tc_backend_auth_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'auto configuration ignores stale runtime backend preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'tc_backend_base_url': 'https://stale.example',
        'tc_backend_enabled': false,
      });

      final settings = await TcBackendSettingsService.autoConfigured().load();
      expect(settings.baseUrl, AppBuildConfig.defaultBackendUrl);
      expect(settings.enabled, isTrue);
    },
  );

  test(
    'build token store creates bearer auth without secure storage',
    () async {
      const store = BuildConfiguredTcBackendTokenStore(token: 'build-token');
      final headers = await TcBackendAuthHeaders(store).build();
      expect(headers['Authorization'], 'Bearer build-token');
    },
  );

  test('empty build token is omitted', () async {
    const store = BuildConfiguredTcBackendTokenStore(token: '  ');
    final headers = await TcBackendAuthHeaders(store).build();
    expect(headers, isNot(contains('Authorization')));
  });
}
