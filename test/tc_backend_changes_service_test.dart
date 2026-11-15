import 'dart:convert';

import 'package:astro_journal/data/models/tc_backend_change.dart';
import 'package:astro_journal/services/tc_backend_changes_service.dart';
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

  test('changes request sends service name and opaque cursor', () async {
    late Uri requested;
    final service = TcBackendChangesService(
      settingsService: settings,
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'data': {
              'changes': [
                {
                  'resource_type': 'ObservationRecord',
                  'resource_id': 'record-1',
                  'operation': 'UPDATE',
                  'revision': 3,
                },
              ],
              'next_cursor': 'cursor-2',
              'has_more': true,
            },
          }),
          200,
        );
      }),
    );

    final page = await service.getChanges(cursor: 'cursor-1');

    expect(requested.path, '/api/common/changes');
    expect(requested.queryParameters['service_name'], 'AstroJournal');
    expect(requested.queryParameters['cursor'], 'cursor-1');
    expect(page.nextCursor, 'cursor-2');
    expect(page.hasMore, isTrue);
    expect(page.changes.single.operation, TcBackendChangeOperation.update);
  });

  test(
    'optional current state fields preserve legacy and unknown responses',
    () async {
      final states = [
        'ACTIVE',
        'DELETED',
        'MISSING',
        'UNAVAILABLE',
        null,
        'FUTURE_STATE',
      ];
      final service = TcBackendChangesService(
        settingsService: settings,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'changes': [
                for (var i = 0; i < states.length; i++)
                  {
                    'resource_type': i == 5 ? 'Equipment' : 'ObservationRecord',
                    'resource_id': 'r$i',
                    'operation': 'UPDATE',
                    'revision': 1,
                    if (i != 4) 'current_resource_state': states[i],
                    'current_revision': i < 4 ? 4 : null,
                  },
                {
                  'resource_type': 'ObservationRecord',
                  'resource_id': 'null',
                  'operation': 'CREATE',
                  'current_resource_state': null,
                },
              ],
              'next_cursor': 'done',
              'has_more': false,
            }),
            200,
          ),
        ),
      );
      final page = await service.getChanges();
      expect(page.changes.map((event) => event.currentResourceState), [
        TcBackendResourceState.active,
        TcBackendResourceState.deleted,
        TcBackendResourceState.missing,
        TcBackendResourceState.unavailable,
        null,
        null,
        null,
      ]);
      expect(
        page.changes.take(4).map((event) => event.currentRevision),
        everyElement(4),
      );
      expect(
        page.changes.skip(4).map((event) => event.currentRevision),
        everyElement(isNull),
      );
      expect(page.nextCursor, 'done');
    },
  );

  test(
    'visibility and unknown resource UPDATE parse without changing operation',
    () async {
      final service = TcBackendChangesService(
        settingsService: settings,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'items': [
                for (final type in ['AstroGalleryVisibility', 'FutureResource'])
                  {
                    'resource_type': type,
                    'resource_id': 'r',
                    'operation': 'UPDATE',
                    'revision': null,
                    'current_revision': 5,
                    'cursor': 9007199254740993,
                    'current_resource_state': 'ACTIVE',
                  },
              ],
              'next_cursor': 9007199254740993,
              'has_more': false,
            }),
            200,
          ),
        ),
      );
      final page = await service.getChanges();
      expect(page.changes.first.isGalleryVisibility, isTrue);
      expect(page.changes.first.isObservationRecord, isFalse);
      expect(page.changes.first.cursor, '9007199254740993');
      expect(page.changes.first.revision, isNull);
      expect(page.changes.last.isGalleryVisibility, isFalse);
      expect(page.changes.last.operation, TcBackendChangeOperation.update);
    },
  );
}
