import 'dart:io';

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

  test('release Maps build contract uses one generated Android resource', () {
    final script = File('scripts/build_app.ps1').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(script, contains(r"$env:GOOGLE_MAPS_API_KEY"));
    expect(script, contains('MAPS_RESOURCE_CONFIGURED=true'));
    expect(gradle, contains('System.getenv("GOOGLE_MAPS_API_KEY")'));
    expect(
      gradle,
      contains('resValue("string", "google_maps_api_key", googleMapsApiKey)'),
    );
    expect(manifest, contains('com.google.android.geo.API_KEY'));
    expect(manifest, contains('@string/google_maps_api_key'));
    expect(manifest, isNot(contains('runtime value synced')));
  });
}
