import 'dart:convert';

import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_exposure_capability.dart';
import 'package:astro_journal/data/models/equipment_remote.dart';
import 'package:astro_journal/services/tc_backend_equipment_service.dart';
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

  test('list parses eyepieces and independent AZ/EQ capabilities', () async {
    final service = TcBackendEquipmentService(
      settingsService: settings,
      client: MockClient((_) async => _jsonResponse([_aggregateJson()])),
    );

    final aggregate = (await service.list()).single;

    expect(aggregate.revision, 4);
    expect(aggregate.equipment.eyepieces.single.name, '25mm');
    expect(
      (aggregate.equipment.azExposureCapability! as DiscreteExposureCapability)
          .valuesSeconds,
      containsAllInOrder([1.0, 1.3, 1.6, 2.5, 3.2]),
    );
    final eq =
        aggregate.equipment.eqExposureCapability as RangeExposureCapability;
    expect(eq.minSeconds, 0.5);
    expect(eq.maxSeconds, 300);
    expect(eq.stepSeconds, 0.5);
  });

  test('create replays the same client UUID and complete aggregate', () async {
    final requests = <http.Request>[];
    final service = TcBackendEquipmentService(
      settingsService: settings,
      client: MockClient((request) async {
        requests.add(request);
        return _jsonResponse(_aggregateJson(), statusCode: 201);
      }),
    );
    final equipment = _equipment();

    await service.create(equipment);
    await service.create(equipment);

    expect(requests, hasLength(2));
    for (final request in requests) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['id'], equipment.id);
      expect(body['eyepieces'], hasLength(1));
      expect(body['az_exposure_capability'], isA<Map>());
      expect(body['eq_exposure_capability'], isA<Map>());
    }
  });

  test('patch and delete carry expected revision', () async {
    late http.Request patch;
    late http.Request delete;
    final service = TcBackendEquipmentService(
      settingsService: settings,
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          patch = request;
          return _jsonResponse(_aggregateJson(revision: 5));
        }
        delete = request;
        return _jsonResponse({
          'equipment_id': _equipmentId,
          'deleted': true,
          'revision': 6,
          'deleted_at': '2026-09-09T01:00:00Z',
        });
      }),
    );

    await service.update(_equipment(), expectedRevision: 4);
    await service.delete(_equipmentId, expectedRevision: 5);

    expect(
      (jsonDecode(patch.body) as Map<String, dynamic>)['expected_revision'],
      4,
    );
    expect(delete.url.queryParameters['expected_revision'], '5');
  });

  test('409 exposes current revision for durable conflict handling', () async {
    final service = TcBackendEquipmentService(
      settingsService: settings,
      client: MockClient(
        (_) async => _jsonResponse({
          'detail': {
            'code': 'REVISION_CONFLICT',
            'equipment_id': _equipmentId,
            'current_revision': 7,
          },
        }, statusCode: 409),
      ),
    );

    await expectLater(
      service.update(_equipment(), expectedRevision: 4),
      throwsA(
        isA<EquipmentRemoteException>()
            .having(
              (error) => error.type,
              'type',
              EquipmentRemoteErrorType.conflict,
            )
            .having((error) => error.currentRevision, 'revision', 7),
      ),
    );
  });

  for (final status in [404, 503]) {
    test('HTTP $status does not become an empty equipment list', () async {
      final service = TcBackendEquipmentService(
        settingsService: settings,
        client: MockClient((_) async => _jsonResponse({}, statusCode: status)),
      );

      await expectLater(
        service.list(),
        throwsA(
          isA<EquipmentRemoteException>().having(
            (error) => error.statusCode,
            'status',
            status,
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

const _equipmentId = '22222222-2222-4222-8222-222222222222';

Equipment _equipment() =>
    EquipmentRemoteAggregate.fromJson(_aggregateJson()).equipment;

Map<String, Object?> _aggregateJson({int revision = 4}) => {
  'id': _equipmentId,
  'name': 'Draco',
  'kind': EquipmentKind.smartTelescope.name,
  'purpose': EquipmentPurpose.imaging.name,
  'is_active': true,
  'focal_length_mm': 240,
  'aperture_mm': 50,
  'fov_width_degrees': 2.0,
  'fov_height_degrees': 1.5,
  'sort_order': 1,
  'eyepieces': [
    {
      'id': '33333333-3333-4333-8333-333333333333',
      'name': '25mm',
      'focal_length_mm': 25,
      'afov_degrees': 60,
      'sort_order': 0,
    },
  ],
  'az_exposure_capability': {
    'type': 'discrete',
    'values_seconds': [1, 1.3, 1.6, 2.5, 3.2],
  },
  'eq_exposure_capability': {
    'type': 'range',
    'min_seconds': 0.5,
    'max_seconds': 300,
    'step_seconds': 0.5,
  },
  'revision': revision,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-09T00:00:00Z',
  'deleted_at': null,
};
