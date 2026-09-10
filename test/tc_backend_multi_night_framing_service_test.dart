import 'dart:convert';

import 'package:astro_journal/data/models/multi_night_framing_reference.dart';
import 'package:astro_journal/services/tc_backend_multi_night_framing_service.dart';
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

  test('list maps catalog and equipment filters and UTF-8 response', () async {
    late http.Request captured;
    final service = TcBackendMultiNightFramingService(
      settingsService: settings,
      client: MockClient((request) async {
        captured = request;
        return _jsonResponse([_json()]);
      }),
    );

    final values = await service.list(
      catalogObjectId: 'M16',
      equipmentId: _equipmentId,
    );

    expect(captured.url.path, TcBackendMultiNightFramingService.path);
    expect(captured.url.queryParameters['catalog_object_id'], 'M16');
    expect(captured.url.queryParameters['equipment_id'], _equipmentId);
    expect(values.single.referenceHourAngleDeg, -18.25);
    expect(values.single.referenceParallacticAngleDeg, 23.75);
    expect(values.single.referenceCapturedAt.timeZoneOffset.inHours, 0);
  });

  test('UTF-8 catalog identity is decoded without corruption', () async {
    final fixture = _json()..['catalog_object_id'] = '사용자 대상';
    final service = TcBackendMultiNightFramingService(
      settingsService: settings,
      client: MockClient((_) async => _jsonResponse([fixture])),
    );

    expect((await service.list()).single.catalogObjectId, '사용자 대상');
  });

  test('POST keeps client UUID and timezone-aware signed HA/PA', () async {
    late Map<String, dynamic> body;
    final service = TcBackendMultiNightFramingService(
      settingsService: settings,
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _jsonResponse(_json(), statusCode: 201);
      }),
    );

    await service.create(_reference());

    expect(body['id'], _referenceId);
    expect(body['catalog_object_id'], 'M16');
    expect(body['reference_hour_angle_deg'], -18.25);
    expect(body['reference_parallactic_angle_deg'], 23.75);
    expect(body['reference_captured_at'], endsWith('Z'));
  });

  test('PATCH and DELETE carry expected revision', () async {
    late http.Request patch;
    late http.Request delete;
    final service = TcBackendMultiNightFramingService(
      settingsService: settings,
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          patch = request;
          return _jsonResponse(_json(revision: 5));
        }
        delete = request;
        return _jsonResponse({
          'reference_id': _referenceId,
          'deleted': true,
          'revision': 6,
          'deleted_at': '2026-07-20T00:00:00Z',
        });
      }),
    );

    await service.update(_reference(), expectedRevision: 4);
    await service.delete(_referenceId, expectedRevision: 5);

    expect(
      (jsonDecode(patch.body) as Map<String, dynamic>)['expected_revision'],
      4,
    );
    expect(delete.url.queryParameters['expected_revision'], '5');
  });

  for (final entry in {
    'REVISION_CONFLICT': MultiNightFramingRemoteErrorType.revisionConflict,
    'REFERENCE_ALREADY_EXISTS':
        MultiNightFramingRemoteErrorType.referenceAlreadyExists,
  }.entries) {
    test('409 ${entry.key} remains distinguishable', () async {
      final service = TcBackendMultiNightFramingService(
        settingsService: settings,
        client: MockClient(
          (_) async => _jsonResponse({
            'detail': {'code': entry.key, 'current_revision': 7},
          }, statusCode: 409),
        ),
      );

      await expectLater(
        service.update(_reference(), expectedRevision: 4),
        throwsA(
          isA<MultiNightFramingRemoteException>().having(
            (error) => error.type,
            'type',
            entry.value,
          ),
        ),
      );
    });
  }
}

http.Response _jsonResponse(Object? body, {int statusCode = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _referenceId = '11111111-1111-4111-8111-111111111111';
const _siteId = '22222222-2222-4222-8222-222222222222';
const _equipmentId = '33333333-3333-4333-8333-333333333333';

MultiNightFramingReference _reference() => MultiNightFramingReference(
  id: _referenceId,
  catalogObjectId: 'M16',
  referenceCapturedAt: DateTime.parse('2026-07-15T21:10:00+09:00'),
  siteId: _siteId,
  equipmentId: _equipmentId,
  referenceHourAngleDeg: -18.25,
  referenceParallacticAngleDeg: 23.75,
  referenceBranch: MultiNightFramingBranch.rising,
  revision: 4,
  createdAt: DateTime.utc(2026, 7, 15),
  updatedAt: DateTime.utc(2026, 7, 16),
);

Map<String, Object?> _json({int revision = 4}) => {
  'id': _referenceId,
  'catalog_object_id': 'M16',
  'reference_captured_at': '2026-07-15T21:10:00+09:00',
  'site_id': _siteId,
  'equipment_id': _equipmentId,
  'reference_hour_angle_deg': -18.25,
  'reference_parallactic_angle_deg': 23.75,
  'reference_branch': 'rising',
  'revision': revision,
  'created_at': '2026-07-15T12:10:00Z',
  'updated_at': '2026-07-16T00:00:00Z',
  'deleted_at': null,
};
