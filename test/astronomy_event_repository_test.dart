import 'dart:convert';

import 'package:astro_journal/data/models/astronomy_event.dart';
import 'package:astro_journal/data/repositories/tc_backend_astronomy_event_repository.dart';
import 'package:astro_journal/services/tc_backend_external_api_client.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tc_backend_base_url': 'https://backend.example',
      'tc_backend_enabled': true,
    });
  });

  test(
    'uses the canonical events endpoint and preserves backend order',
    () async {
      final repository = _repository((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/astro/events');
        expect(request.url.queryParameters, isEmpty);
        return _jsonResponse({
          'events': [
            {
              'id': 'meteor-1',
              'type': 'meteor_shower',
              'title': '첫 번째 이벤트',
              'start_at': '2026-08-10T12:00:00Z',
              'peak_at': '2026-08-12T12:00:00Z',
              'end_at': '2026-08-13T12:00:00Z',
              'tags': ['달빛 적음', '북동쪽'],
              'priority': 20,
            },
            {
              'id': 'eclipse-1',
              'type': 'lunar_eclipse',
              'title': '두 번째 이벤트',
              'peak_at': '2026-09-08T18:00:00Z',
              'tags': [],
              'priority': 10,
            },
          ],
        });
      });

      final events = await repository.getUpcomingEvents();

      expect(events.map((event) => event.id), ['meteor-1', 'eclipse-1']);
      expect(events.first.type, AstronomyEventType.meteorShower);
      expect(events.first.peakAt?.isUtc, isTrue);
      expect(events.first.tags, ['달빛 적음', '북동쪽']);
    },
  );

  test('adds optional UTC range only when explicitly supplied', () async {
    final repository = _repository((request) async {
      expect(request.url.queryParameters['from'], '2026-01-01T00:00:00.000Z');
      expect(request.url.queryParameters['to'], '2026-02-01T00:00:00.000Z');
      return _jsonResponse({'events': <Object>[]});
    });

    await repository.getUpcomingEvents(
      from: DateTime.utc(2026, 1),
      to: DateTime.utc(2026, 2),
    );
  });

  test('rejects malformed event collections without partial mapping', () async {
    final repository = _repository(
      (_) async => _jsonResponse({
        'events': [
          {
            'id': 'broken',
            'type': 'conjunction',
            'title': '잘못된 이벤트',
            'peak_at': 'not-a-date',
            'tags': [],
            'priority': 1,
          },
        ],
      }),
    );

    await expectLater(
      repository.getUpcomingEvents(),
      throwsA(
        isA<TcBackendExternalApiException>().having(
          (error) => error.code,
          'code',
          TcBackendExternalApiErrorCode.malformedResponse,
        ),
      ),
    );
  });
}

TcBackendAstronomyEventRepository _repository(
  Future<http.Response> Function(http.Request request) handler,
) {
  return TcBackendAstronomyEventRepository(
    TcBackendExternalApiClient(
      settingsService: TcBackendSettingsService(),
      client: MockClient(handler),
    ),
  );
}

http.Response _jsonResponse(Map<String, Object?> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
