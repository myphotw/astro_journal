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
}
