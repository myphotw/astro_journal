import 'dart:convert';

import 'package:astro_journal/services/tc_backend_auth_service.dart';
import 'package:astro_journal/services/tc_backend_catalog_favorite_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late TcBackendSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
  });

  test(
    'list add and remove use the shared authenticated API contract',
    () async {
      final requests = <http.Request>[];
      final service = TcBackendCatalogFavoriteService(
        settingsService: settings,
        authHeaders: TcBackendAuthHeaders(
          const BuildConfiguredTcBackendTokenStore(token: 'favorite-token'),
        ),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return _jsonResponse([_favorite('solar_6')]);
          }
          if (request.method == 'POST') {
            return _jsonResponse(_favorite('NGC2237'));
          }
          return _jsonResponse({
            'catalog_object_id': 'NGC2237',
            'deleted': true,
          });
        }),
      );

      expect((await service.list()).single.catalogObjectId, 'solar_6');
      expect((await service.add('NGC2237')).catalogObjectId, 'NGC2237');
      expect((await service.remove('NGC2237')).deleted, isTrue);

      expect(requests.map((request) => request.method), [
        'GET',
        'POST',
        'DELETE',
      ]);
      expect(
        requests.every(
          (request) =>
              request.headers['Authorization'] == 'Bearer favorite-token',
        ),
        isTrue,
      );
      expect(requests[0].url.path, '/api/astro/catalog-favorites');
      expect(jsonDecode(requests[1].body), {'catalog_object_id': 'NGC2237'});
      expect(requests[2].url.path, '/api/astro/catalog-favorites/NGC2237');
    },
  );

  test('network failure is explicit and never reported as success', () async {
    final service = TcBackendCatalogFavoriteService(
      settingsService: settings,
      client: MockClient(
        (_) async => _jsonResponse({'detail': 'offline'}, statusCode: 503),
      ),
    );

    await expectLater(
      service.add('solar_6'),
      throwsA(
        isA<CatalogFavoriteRemoteException>().having(
          (error) => error.type,
          'type',
          CatalogFavoriteRemoteErrorType.server,
        ),
      ),
    );
  });
}

Map<String, dynamic> _favorite(String id) => {
  'catalog_object_id': id,
  'created_at': '2026-10-21T00:00:00Z',
  'updated_at': '2026-10-21T00:00:00Z',
};

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
