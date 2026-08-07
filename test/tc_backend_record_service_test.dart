import 'dart:convert';

import 'package:astro_journal/data/models/backend_upload_result.dart';
import 'package:astro_journal/services/tc_backend_record_service.dart';
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

  test('PATCH sends only revision and explicit partial fields', () async {
    late http.Request sent;
    final service = TcBackendRecordService(
      settingsService: settings,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'record_id': 'record-1',
            'revision': 4,
            'favorite': true,
          }),
          200,
        );
      }),
    );

    final result = await service.patchRecord('record-1', 3, {'favorite': true});

    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/astro/records/record-1');
    expect(jsonDecode(sent.body), {'revision': 3, 'favorite': true});
    expect(result.revision, 4);
    expect(result.canonicalFields['favorite'], isTrue);
  });

  test('DELETE parses an idempotent soft-delete tombstone', () async {
    final service = TcBackendRecordService(
      settingsService: settings,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'record_id': 'record-1',
            'deleted': true,
            'revision': 5,
            'deleted_at': '2026-08-07T01:02:03Z',
          }),
          200,
        ),
      ),
    );

    final result = await service.deleteRecord('record-1');

    expect(result.recordId, 'record-1');
    expect(result.revision, 5);
    expect(result.deletedAt, DateTime.utc(2026, 8, 7, 1, 2, 3));
  });

  test('409 preserves current revision and is not retryable', () async {
    final service = TcBackendRecordService(
      settingsService: settings,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': {
              'code': 'REVISION_CONFLICT',
              'record_id': 'record-1',
              'expected_revision': 3,
              'current_revision': 4,
            },
          }),
          409,
        ),
      ),
    );

    await expectLater(
      service.patchRecord('record-1', 3, {'memo': 'local'}),
      throwsA(
        isA<TcBackendRecordException>()
            .having(
              (error) => error.type,
              'type',
              BackendUploadErrorType.http409,
            )
            .having((error) => error.currentRevision, 'currentRevision', 4)
            .having((error) => error.isRetryable, 'isRetryable', isFalse),
      ),
    );
  });

  test('HTTP 5xx remains retryable', () async {
    final service = TcBackendRecordService(
      settingsService: settings,
      client: MockClient((_) async => http.Response('{}', 503)),
    );

    await expectLater(
      service.patchRecord('record-1', 3, {'memo': 'local'}),
      throwsA(
        isA<TcBackendRecordException>()
            .having(
              (error) => error.type,
              'type',
              BackendUploadErrorType.http5xx,
            )
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });
}
