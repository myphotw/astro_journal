import 'package:astro_journal/data/models/tc_backend_models.dart';
import 'package:astro_journal/features/settings/viewmodel/tc_backend_view_model.dart';
import 'package:astro_journal/services/tc_backend_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TcBackendSettings', () {
    test('normalizes a trailing slash', () {
      expect(
        TcBackendSettings.normalizeBaseUrl(' http://host:8000/ '),
        'http://host:8000',
      );
    });

    test('rejects invalid or path URLs', () {
      expect(TcBackendSettings.normalizeBaseUrl('host:8000'), isNull);
      expect(TcBackendSettings.normalizeBaseUrl('https://host/api'), isNull);
      expect(TcBackendSettings.normalizeBaseUrl('ftp://host'), isNull);
    });

    test('persists base URL and enabled state', () async {
      SharedPreferences.setMockInitialValues({});
      final service = TcBackendSettingsService();
      await service.save(
        const TcBackendSettings(baseUrl: 'https://host/', enabled: true),
      );

      final settings = await service.load();
      expect(settings.baseUrl, 'https://host');
      expect(settings.enabled, isTrue);
    });
  });

  group('TcBackendService', () {
    test('keeps backend disabled as not configured without HTTP', () async {
      final viewModel = TcBackendViewModel(
        TcBackendSettingsService(),
        serviceFactory: (_) => throw StateError('HTTP must not be created'),
      );

      await viewModel.testConnection(
        baseUrl: 'http://host:8000',
        enabled: false,
      );

      expect(viewModel.status, TcBackendConnectionStatus.notConfigured);
    });

    test('parses health and compatible capabilities', () async {
      final service = _service((request) {
        if (request.url.path.endsWith('/health')) {
          return http.Response(
            '{"status":"ok","database":"ok","storage":"ok","vision":"ok"}',
            200,
          );
        }
        return http.Response(
          '{"api_version":"1.1","service_version":"B1","supported_services":["AstroJournal"],"upload_contract":{"supports_service_name":true,"supports_client_file_id":true}}',
          200,
        );
      });

      final result = await service.checkCompatibility();
      expect(result.status, TcBackendConnectionStatus.connected);
      expect(result.health?.database, 'ok');
      expect(result.capabilities?.apiVersion, '1.1');
    });

    test('reports incompatible when AstroJournal is absent', () async {
      final service = _service(
        (request) => http.Response(
          request.url.path.endsWith('/health')
              ? '{"status":"ok"}'
              : '{"supported_services":["MemoryKeeper"],"upload_contract":{"supports_service_name":true,"supports_client_file_id":true}}',
          200,
        ),
      );

      expect(
        (await service.checkCompatibility()).status,
        TcBackendConnectionStatus.incompatible,
      );
    });

    test('reports incompatible when client_file_id is unsupported', () async {
      final service = _service(
        (request) => http.Response(
          request.url.path.endsWith('/health')
              ? '{"status":"ok"}'
              : '{"supported_services":["AstroJournal"],"upload_contract":{"supports_service_name":true,"supports_client_file_id":false}}',
          200,
        ),
      );

      expect(
        (await service.checkCompatibility()).status,
        TcBackendConnectionStatus.incompatible,
      );
    });

    test('accepts degraded health when upload contract is compatible', () async {
      final service = _service(
        (request) => http.Response(
          request.url.path.endsWith('/health')
              ? '{"status":"degraded","weather":"failed"}'
              : '{"supported_services":["AstroJournal"],"upload_contract":{"supports_service_name":true,"supports_client_file_id":true}}',
          200,
        ),
      );

      expect(
        (await service.checkCompatibility()).status,
        TcBackendConnectionStatus.degraded,
      );
    });

    test('reports unreachable server', () async {
      final service = TcBackendService(
        baseUrl: 'http://host:8000',
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      expect(
        (await service.checkCompatibility()).status,
        TcBackendConnectionStatus.unreachable,
      );
    });
  });
}

TcBackendService _service(
  http.Response Function(http.Request request) handler,
) {
  return TcBackendService(
    baseUrl: 'http://host:8000',
    client: MockClient((request) async => handler(request)),
  );
}
