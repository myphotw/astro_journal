import 'dart:convert';

import 'package:astro_journal/services/tc_backend_astrojournal_reset_service.dart';
import 'package:astro_journal/services/tc_backend_auth_service.dart';
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

  test('preview calls exact API and maps Backend schema counts', () async {
    late http.Request request;
    final service = TcBackendAstroJournalResetService(
      settingsService: settings,
      authHeaders: TcBackendAuthHeaders(
        const BuildConfiguredTcBackendTokenStore(token: 'secret-token'),
      ),
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_previewJson), 200);
      }),
    );

    final preview = await service.preview();

    expect(request.method, 'POST');
    expect(request.url.path, '/api/astro/reset/preview');
    expect(request.headers['Authorization'], 'Bearer secret-token');
    expect(preview.observationRecordCount, 127);
    expect(preview.astroFileCount, 84);
    expect(preview.astroOnlyFileCount, 80);
    expect(preview.sharedFileCount, 4);
    expect(preview.processingJobCount, 0);
    expect(preview.physicalOriginalDeleteCount, 80);
    expect(preview.physicalPreviewDeleteCount, 80);
    expect(preview.physicalThumbnailDeleteCount, 79);
    expect(preview.preservedSharedFileCount, 4);
    expect(preview.resetBlocked, isFalse);
  });

  test('execute sends exact confirmation and maps reset cursor', () async {
    late http.Request request;
    final service = TcBackendAstroJournalResetService(
      settingsService: settings,
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_executeJson), 200);
      }),
    );

    final result = await service.execute();

    expect(request.url.path, '/api/astro/reset/execute');
    expect(jsonDecode(request.body), {'confirmation': 'RESET_ASTROJOURNAL'});
    expect(result.resetCompleted, isTrue);
    expect(result.deletedObservationRecordCount, 127);
    expect(result.preservedSharedFileCount, 4);
    expect(result.resetEventCursor, 912);
  });

  test(
    '409 technical code maps to blocked without exposing it to user',
    () async {
      final service = TcBackendAstroJournalResetService(
        settingsService: settings,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'detail': {
                'code': 'ASTROJOURNAL_RESET_BLOCKED',
                'processing_upload_count': 1,
                'processing_vision_job_count': 0,
              },
            }),
            409,
          ),
        ),
      );

      await expectLater(
        service.execute(),
        throwsA(
          isA<AstroJournalResetException>()
              .having(
                (error) => error.type,
                'type',
                AstroJournalResetErrorType.blocked,
              )
              .having((error) => error.statusCode, 'statusCode', 409)
              .having(
                (error) => error.userMessage,
                'userMessage',
                isNot(contains('ASTROJOURNAL_RESET_BLOCKED')),
              ),
        ),
      );
    },
  );

  test('500 and malformed success response are rejected', () async {
    final serverError = TcBackendAstroJournalResetService(
      settingsService: settings,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    await expectLater(
      serverError.execute(),
      throwsA(
        isA<AstroJournalResetException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );

    final malformed = TcBackendAstroJournalResetService(
      settingsService: settings,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.preview(),
      throwsA(
        isA<AstroJournalResetException>().having(
          (error) => error.type,
          'type',
          AstroJournalResetErrorType.malformedResponse,
        ),
      ),
    );
  });
}

const _previewJson = <String, Object?>{
  'observation_record_count': 127,
  'astro_file_count': 84,
  'astro_only_file_count': 80,
  'shared_file_count': 4,
  'plate_solve_result_count': 2,
  'photo_object_count': 3,
  'upload_job_count': 6,
  'pending_upload_count': 1,
  'processing_upload_count': 0,
  'processing_vision_job_count': 0,
  'processing_job_count': 0,
  'physical_original_delete_count': 80,
  'physical_preview_delete_count': 80,
  'physical_thumbnail_delete_count': 79,
  'preserved_shared_file_count': 4,
  'reset_blocked': false,
  'blocked_reason': null,
};

const _executeJson = <String, Object?>{
  'reset_completed': true,
  'deleted_observation_record_count': 127,
  'removed_astro_file_link_count': 84,
  'tombstoned_common_file_count': 80,
  'preserved_shared_file_count': 4,
  'deleted_upload_job_count': 6,
  'deleted_original_count': 80,
  'deleted_preview_count': 80,
  'deleted_thumbnail_count': 79,
  'deleted_plate_solve_result_count': 2,
  'deleted_photo_object_count': 3,
  'reset_event_cursor': 912,
};
