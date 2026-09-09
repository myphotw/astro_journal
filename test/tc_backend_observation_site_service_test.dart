import 'dart:convert';

import 'package:astro_journal/data/models/blocked_azimuth_range.dart';
import 'package:astro_journal/data/models/horizon_point.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/services/tc_backend_observation_site_service.dart';
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

  test('list parses canonical aggregate and circular blocked range', () async {
    final service = TcBackendObservationSiteService(
      settingsService: settings,
      client: MockClient((_) async => _jsonResponse([_json()])),
    );

    final aggregate = (await service.list()).single;

    expect(aggregate.revision, 4);
    expect(
      aggregate.site.horizonPoints.single.source,
      HorizonDataSource.cameraScan,
    );
    expect(aggregate.site.blockedAzimuthRanges.single.startAzimuth, 350);
    expect(aggregate.site.blockedAzimuthRanges.single.endAzimuth, 20);
  });

  test(
    'create replays UUID but omits an unresolved equipment reference',
    () async {
      final requests = <http.Request>[];
      final service = TcBackendObservationSiteService(
        settingsService: settings,
        client: MockClient((request) async {
          requests.add(request);
          return _jsonResponse(_json(), statusCode: 201);
        }),
        canReferenceDefaultEquipment: (_) async => false,
      );
      final site = _site();

      await service.create(site);
      await service.create(site);

      expect(requests, hasLength(2));
      for (final request in requests) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['id'], site.id);
        expect(body.containsKey('default_equipment_id'), isFalse);
      }
    },
  );

  test(
    'create wires default equipment after Equipment sync resolves it',
    () async {
      late http.Request request;
      final service = TcBackendObservationSiteService(
        settingsService: settings,
        client: MockClient((value) async {
          request = value;
          return _jsonResponse(_json(), statusCode: 201);
        }),
        canReferenceDefaultEquipment: (_) async => true,
      );

      await service.create(_site());

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['default_equipment_id'], _site().defaultEquipmentId);
    },
  );

  test('patch and delete carry expected revision', () async {
    late http.Request patch;
    late http.Request delete;
    final service = TcBackendObservationSiteService(
      settingsService: settings,
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          patch = request;
          return _jsonResponse(_json(revision: 5));
        }
        delete = request;
        return _jsonResponse({
          'site_id': _siteId,
          'deleted': true,
          'revision': 6,
          'deleted_at': '2026-09-09T01:00:00Z',
        });
      }),
    );

    await service.update(_site(), expectedRevision: 4);
    await service.delete(_siteId, expectedRevision: 5);

    expect(
      (jsonDecode(patch.body) as Map<String, dynamic>)['expected_revision'],
      4,
    );
    expect(delete.url.queryParameters['expected_revision'], '5');
  });

  test('409 retains current revision for durable conflict handling', () async {
    final service = TcBackendObservationSiteService(
      settingsService: settings,
      client: MockClient(
        (_) async => _jsonResponse({
          'detail': {
            'code': 'REVISION_CONFLICT',
            'site_id': _siteId,
            'expected_revision': 3,
            'current_revision': 4,
          },
        }, statusCode: 409),
      ),
    );

    await expectLater(
      service.update(_site(), expectedRevision: 3),
      throwsA(
        isA<ObservationSiteRemoteException>()
            .having(
              (error) => error.type,
              'type',
              ObservationSiteRemoteErrorType.conflict,
            )
            .having((error) => error.currentRevision, 'revision', 4),
      ),
    );
  });

  for (final status in [404, 503]) {
    test(
      'HTTP $status is classified without returning an empty server list',
      () async {
        final service = TcBackendObservationSiteService(
          settingsService: settings,
          client: MockClient(
            (_) async => _jsonResponse({}, statusCode: status),
          ),
        );

        await expectLater(
          service.list(),
          throwsA(
            isA<ObservationSiteRemoteException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
      },
    );
  }
}

http.Response _jsonResponse(Object? body, {int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _siteId = '11111111-1111-4111-8111-111111111111';

ObservationSite _site() => ObservationSite(
  id: _siteId,
  name: '강원 관측지',
  address: '강원도',
  latitude: 37.25,
  longitude: 128.25,
  bortle: 3,
  sqm: 21.3,
  brightnessGrade: 'dark',
  trackingMode: TrackingMode.altAz,
  defaultEquipmentId: '22222222-2222-4222-8222-222222222222',
  defaultMinAltitude: 20,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 2),
  horizonPoints: const [
    HorizonPoint(
      id: '33333333-3333-4333-8333-333333333333',
      observationSiteId: _siteId,
      azimuth: 0,
      minAltitude: 15,
      source: HorizonDataSource.cameraScan,
    ),
  ],
  blockedAzimuthRanges: const [
    BlockedAzimuthRange(
      id: '44444444-4444-4444-8444-444444444444',
      observationSiteId: _siteId,
      startAzimuth: 350,
      endAzimuth: 20,
    ),
  ],
);

Map<String, Object?> _json({int revision = 4}) => {
  'id': _siteId,
  'name': '강원 관측지',
  'latitude': 37.25,
  'longitude': 128.25,
  'address': '강원도',
  'bortle': 3,
  'sqm': 21.3,
  'brightness_grade': 'dark',
  'is_favorite': true,
  'tracking_mode': 'altAz',
  'default_equipment_id': null,
  'default_min_altitude': 20,
  'default_max_altitude': null,
  'preferred_start': '20:30',
  'preferred_end': '04:30',
  'memo': '',
  'horizon_points': [
    {
      'id': '33333333-3333-4333-8333-333333333333',
      'observation_site_id': _siteId,
      'azimuth': 0,
      'min_altitude': 15,
      'max_altitude': null,
      'sort_order': 0,
      'source': 'camera_scan',
    },
  ],
  'blocked_azimuth_ranges': [
    {
      'id': '44444444-4444-4444-8444-444444444444',
      'observation_site_id': _siteId,
      'start_azimuth': 350,
      'end_azimuth': 20,
      'reason': null,
      'source': 'manual',
    },
  ],
  'revision': revision,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-02T00:00:00Z',
  'deleted_at': null,
};
