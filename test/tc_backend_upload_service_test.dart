import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/data/models/backend_upload_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_upload_service.dart';

void main() {
  late Directory temp;
  late File photo;
  late TcBackendSettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    temp = await Directory.systemTemp.createTemp('astro_upload_test_');
    photo = File('${temp.path}/sample.jpg');
    await photo.writeAsBytes(utf8.encode('astro-journal-photo'));
  });
  tearDown(() => temp.delete(recursive: true));

  ShootingRecord record() => ShootingRecord(
    id: 'local-record',
    celestialObjectId: 'M42',
    capturedAt: DateTime.parse('2026-01-02T03:04:05+09:00'),
    photoUri: photo.path,
    memo: 'Orion',
    location: 'Seoul',
    createdAt: DateTime.now(),
    isFavorite: true,
    isRepresentative: true,
  );

  test('disabled backend makes no network call', () async {
    var calls = 0;
    final service = TcBackendUploadService(
      settingsService: settings,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 500);
      }),
    );
    final result = await service.uploadRecord(record());
    expect(result.attempted, isFalse);
    expect(calls, 0);
  });

  test('uploads, polls and creates an observation record', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final requests = <http.Request>[];
    final service = TcBackendUploadService(
      settingsService: settings,
      delay: (_) async {},
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/upload')) {
          return http.Response(
            jsonEncode({'job_id': 'job-1', 'status': 'WAITING'}),
            200,
          );
        }
        if (request.url.path.endsWith('/jobs/job-1')) {
          return http.Response(
            jsonEncode({'status': 'COMPLETED', 'backend_file_id': 'sha-file'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({'record_id': 'record-1', 'revision': 2}),
          201,
        );
      }),
    );
    final result = await service.uploadRecord(record());
    expect(result.success, isTrue);
    expect(result.backendFileId, 'sha-file');
    expect(result.backendRecordId, 'record-1');
    expect(result.recordRevision, 2);
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['catalog_object_id'], 'M42');
    expect(body['captured_at'], '2026-01-01T18:04:05.000Z');
    expect(body['location_name'], 'Seoul');
  });

  test('returns job failure and lowercase streaming SHA-256', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final service = TcBackendUploadService(
      settingsService: settings,
      delay: (_) async {},
      client: MockClient(
        (request) async => request.url.path.endsWith('/upload')
            ? http.Response(jsonEncode({'job_id': 'job-fail'}), 200)
            : http.Response(jsonEncode({'status': 'FAILED'}), 200),
      ),
    );
    final hash = await service.contentSha256(photo);
    expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    final result = await service.uploadRecord(record());
    expect(result.errorType, BackendUploadErrorType.jobFailed);
  });

  test('handles upload conflict and record creation failure', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    final conflict = TcBackendUploadService(
      settingsService: settings,
      client: MockClient((_) async => http.Response('{}', 409)),
    );
    expect(
      (await conflict.uploadRecord(record())).errorType,
      BackendUploadErrorType.idempotencyConflict,
    );

    final recordFailure = TcBackendUploadService(
      settingsService: settings,
      delay: (_) async {},
      client: MockClient((request) async {
        if (request.url.path.endsWith('/upload')) {
          return http.Response(
            jsonEncode({'job_id': 'done', 'backend_file_id': 'file'}),
            200,
          );
        }
        return http.Response('{}', 500);
      }),
    );
    expect(
      (await recordFailure.uploadRecord(record())).errorType,
      BackendUploadErrorType.recordCreateFailed,
    );
  });

  test('polling continues from WAITING and PROCESSING until completed', () async {
    await settings.save(const TcBackendSettings(
      baseUrl: 'https://backend.example', enabled: true,
    ));
    for (final initial in ['WAITING', 'PROCESSING']) {
      var calls = 0;
      final service = TcBackendUploadService(
        settingsService: settings,
        delay: (_) async {},
        client: MockClient((_) async {
          calls++;
          return http.Response(jsonEncode(calls == 1
              ? {'status': initial}
              : {'status': 'COMPLETED', 'backend_file_id': 'file-$initial'}), 200);
        }),
      );
      final result = await service.pollUploadJob('job-$initial');
      expect(result.status, TcBackendUploadJobStatus.completed);
      expect(result.backendFileId, 'file-$initial');
      expect(calls, 2);
    }
  });

  test('polling rejects malformed, failed, and unknown job responses', () async {
    await settings.save(const TcBackendSettings(
      baseUrl: 'https://backend.example', enabled: true,
    ));
    Future<void> expectJob(Map<String, dynamic> body, BackendUploadErrorType type) async {
      final service = TcBackendUploadService(
        settingsService: settings,
        delay: (_) async {},
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );
      await expectLater(service.pollUploadJob('job'), throwsA(isA<TcBackendUploadException>().having((e) => e.type, 'type', type)));
    }
    await expectJob({'status': 'COMPLETED'}, BackendUploadErrorType.malformedResponse);
    await expectJob({'status': 'FAILED'}, BackendUploadErrorType.jobFailed);
    await expectJob({'status': 'UNKNOWN'}, BackendUploadErrorType.malformedResponse);
  });
}
