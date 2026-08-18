import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/data/models/backend_upload_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/tc_backend_models.dart';
import 'package:astro_journal/services/tc_backend_auth_service.dart';
import 'package:astro_journal/services/tc_backend_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_upload_service.dart';
import 'package:astro_journal/services/tc_backend_external_api_client.dart';
import 'package:astro_journal/services/tc_backend_changes_service.dart';
import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('secure token storage supports save, update, and delete', () async {
    final service = TcBackendAuthService();
    expect(await service.readToken(), isNull);
    await service.saveToken(' first-token ');
    expect(await service.readToken(), 'first-token');
    await service.saveToken('second-token');
    expect(await service.readToken(), 'second-token');
    await service.deleteToken();
    expect(await service.readToken(), isNull);
  });

  test(
    'common headers omit or add Bearer without putting it in URLs',
    () async {
      final empty = TcBackendAuthHeaders(const EmptyTcBackendTokenStore());
      expect((await empty.build()).containsKey('Authorization'), isFalse);

      final store = _MemoryTokenStore('secret-token');
      final headers = await TcBackendAuthHeaders(store).build(json: true);
      expect(headers['Authorization'], 'Bearer secret-token');
      expect(headers['Content-Type'], 'application/json');
    },
  );

  test(
    'public health omits auth and protected readiness includes it',
    () async {
      final requests = <http.Request>[];
      final service = TcBackendService(
        baseUrl: 'https://nas.example:8443',
        authHeaders: TcBackendAuthHeaders(_MemoryTokenStore('client-token')),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/health') {
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          }
          if (request.url.path.endsWith('/capabilities')) {
            return http.Response(
              jsonEncode({
                'supported_services': ['AstroJournal'],
                'upload_contract': {
                  'supports_service_name': true,
                  'supports_client_file_id': true,
                },
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'services': {}}), 200);
        }),
      );
      expect((await service.checkCompatibility()).isCompatible, isTrue);
      expect(requests.first.url.path, '/health');
      expect(requests.first.headers.containsKey('Authorization'), isFalse);
      expect(
        requests
            .skip(1)
            .every(
              (request) =>
                  request.headers['Authorization'] == 'Bearer client-token',
            ),
        isTrue,
      );
      expect(requests.first.url.port, 8443);
    },
  );

  test('protected 401 is reported as authentication failure', () async {
    final service = TcBackendService(
      baseUrl: 'https://nas.example',
      authHeaders: TcBackendAuthHeaders(_MemoryTokenStore('wrong-token')),
      client: MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }
        return http.Response('{}', 401);
      }),
    );
    final result = await service.checkCompatibility();
    expect(result.status, TcBackendConnectionStatus.authenticationFailed);
    expect(result.message, contains('authentication failed'));
  });

  test('multipart upload includes Bearer and maps 401 safely', () async {
    final settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://nas.example:9443',
        enabled: true,
      ),
    );
    final temp = await Directory.systemTemp.createTemp('astro_auth_upload_');
    addTearDown(() => temp.delete(recursive: true));
    final photo = File('${temp.path}/photo.jpg');
    await photo.writeAsBytes([1, 2, 3]);
    late http.Request captured;
    final service = TcBackendUploadService(
      settingsService: settings,
      authHeaders: TcBackendAuthHeaders(_MemoryTokenStore('upload-token')),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 401);
      }),
    );
    final record = ShootingRecord(
      id: 'local-1',
      celestialObjectId: 'M42',
      capturedAt: DateTime.utc(2026),
      photoUri: photo.path,
      createdAt: DateTime.utc(2026),
    );
    final result = await service.uploadRecord(record);
    expect(captured.headers['Authorization'], 'Bearer upload-token');
    expect(result.errorType, BackendUploadErrorType.unauthorized);
    expect(captured.url.query, isEmpty);
  });

  test('media auth is limited to matching protected backend origin', () async {
    final settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://nas.example:8443',
        enabled: true,
      ),
    );
    final media = TcBackendMediaAuthService(
      settings,
      TcBackendAuthHeaders(_MemoryTokenStore('media-token')),
    );
    expect(
      (await media.headersFor(
        'https://nas.example:8443/api/common/gallery/file/thumbnail',
      ))['Authorization'],
      'Bearer media-token',
    );
    expect(
      await media.headersFor('https://other.example/api/common/file'),
      isEmpty,
    );
    expect(await media.headersFor('https://nas.example:8443/health'), isEmpty);
    final relative = await media.requestFor('/api/common/gallery/1/preview');
    expect(
      relative.url,
      'https://nas.example:8443/api/common/gallery/1/preview',
    );
    expect(relative.headers['Authorization'], 'Bearer media-token');
  });

  test('JSON GET and POST external API requests include Bearer', () async {
    final settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://nas.example:8443',
        enabled: true,
      ),
    );
    final requests = <http.Request>[];
    final client = TcBackendExternalApiClient(
      settingsService: settings,
      authHeaders: TcBackendAuthHeaders(_MemoryTokenStore('external-token')),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'data': {'ok': true},
          }),
          200,
        );
      }),
    );
    await client.getMap('/api/external/test');
    await client.postMap('/api/external/test', body: {'value': 1});
    expect(requests, hasLength(2));
    expect(
      requests.every(
        (request) =>
            request.headers['Authorization'] == 'Bearer external-token',
      ),
      isTrue,
    );
    expect(requests.last.headers['Content-Type'], contains('application/json'));
  });

  test('changes and gallery data requests include Bearer', () async {
    final settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(baseUrl: 'https://nas.example', enabled: true),
    );
    final seen = <http.Request>[];
    final httpClient = MockClient((request) async {
      seen.add(request);
      if (request.url.path.endsWith('/changes')) {
        return http.Response(
          jsonEncode({'changes': [], 'has_more': false}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            {
              'record_id': 'record-1',
              'file_id': 'sha-1',
              'catalog_object_id': 'M42',
              'captured_at': '2026-01-01T00:00:00Z',
              'favorite': false,
              'representative': false,
              'thumbnail_url': '/api/media/thumb',
              'preview_url': '/api/media/preview',
              'original_url': '/api/media/original',
              'revision': 1,
            },
          ],
        }),
        200,
      );
    });
    final headers = TcBackendAuthHeaders(_MemoryTokenStore('read-token'));
    await TcBackendChangesService(
      settingsService: settings,
      client: httpClient,
      authHeaders: headers,
    ).getChanges();
    await RemoteGalleryDataSource(
      baseUrl: 'https://nas.example',
      client: httpClient,
      authHeaders: headers,
    ).getGallery();
    expect(seen, hasLength(2));
    expect(
      seen.every(
        (request) => request.headers['Authorization'] == 'Bearer read-token',
      ),
      isTrue,
    );
  });
}

class _MemoryTokenStore implements TcBackendTokenStore {
  _MemoryTokenStore(this.token);
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> deleteToken() async => token = null;
}
