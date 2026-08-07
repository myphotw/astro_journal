import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/data/models/backend_upload_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/sync_outbox_item.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_sync_coordinator.dart';
import 'package:astro_journal/services/tc_backend_upload_service.dart';

void main() {
  late TcBackendSettingsService settings;
  late ShootingRecord record;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    record = ShootingRecord(
      id: 'local-record',
      celestialObjectId: 'M42',
      capturedAt: DateTime.utc(2026),
      photoUri: 'photo.jpg',
      createdAt: DateTime.utc(2026),
    );
  });

  SyncOutboxItem item({
    SyncOutboxState state = SyncOutboxState.queued,
    String? jobId,
    String? fileId,
    String? recordId,
    int retryCount = 0,
    DateTime? retryAt,
    String? error,
  }) => SyncOutboxItem(
    operationId: 'operation',
    localRecordId: record.id,
    clientFileId: 'stable-client-id',
    clientRecordId: 'client-record-id',
    payload: const {},
    state: state,
    uploadJobId: jobId,
    backendFileId: fileId,
    backendRecordId: recordId,
    retryCount: retryCount,
    nextRetryAt: retryAt,
    lastError: error,
  );

  test('resumes from upload_job_id without retransmitting upload', () async {
    final outbox = _FakeOutbox(
      item(state: SyncOutboxState.processing, jobId: 'job'),
    );
    final upload = _FakeStages();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();
    expect(upload.startCalls, 0);
    expect(upload.pollCalls, 1);
    expect(upload.recordCalls, 1);
    expect(outbox.synced, isTrue);
  });

  test('resumes from backend_file_id without upload or polling', () async {
    final outbox = _FakeOutbox(
      item(state: SyncOutboxState.recordCreating, fileId: 'file'),
    );
    final upload = _FakeStages();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();
    expect(upload.startCalls, 0);
    expect(upload.pollCalls, 0);
    expect(upload.recordCalls, 1);
  });

  test('backend_record_id marks synced without record POST', () async {
    final outbox = _FakeOutbox(
      item(
        state: SyncOutboxState.recordCreating,
        fileId: 'file',
        recordId: 'remote-record',
      ),
    );
    final upload = _FakeStages();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();
    expect(upload.recordCalls, 0);
    expect(outbox.synced, isTrue);
  });

  test('queued upload preserves client_file_id', () async {
    final outbox = _FakeOutbox(item());
    final upload = _FakeStages();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();
    expect(upload.clientFileId, 'stable-client-id');
  });

  test(
    'retryable and non-retryable failures are persisted correctly',
    () async {
      for (final entry in <BackendUploadErrorType, bool>{
        BackendUploadErrorType.network: true,
        BackendUploadErrorType.http409: false,
      }.entries) {
        final outbox = _FakeOutbox(item());
        final upload = _FakeStages(
          error: TcBackendUploadException(entry.key, 'failed'),
        );
        await TcBackendSyncCoordinator(
          outbox,
          _FakeRecords(record),
          settings,
          upload,
          now: () => DateTime.utc(2026),
        ).drain();
        expect(outbox.lastState, SyncOutboxState.failed);
        expect(outbox.lastError, startsWith('${entry.key.name}|'));
        expect(outbox.nextRetryAt != null, entry.value);
        expect(outbox.patches.any((p) => p['retry_count'] == 1), isTrue);
      }
    },
  );

  test('duplicate drain does not process the same item twice', () async {
    final gate = Completer<UploadStartResult>();
    final outbox = _FakeOutbox(item());
    final upload = _FakeStages(startGate: gate);
    final coordinator = TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    );
    final first = coordinator.drain();
    await Future<void>.delayed(Duration.zero);
    await coordinator.drain();
    expect(upload.startCalls, 1);
    gate.complete(const UploadStartResult(uploadJobId: 'job'));
    await first;
  });
}

class _FakeOutbox implements SyncOutboxRepository {
  _FakeOutbox(this.item);
  final SyncOutboxItem item;
  final List<Map<String, Object?>> patches = [];
  SyncOutboxState? lastState;
  String? lastError;
  DateTime? nextRetryAt;
  bool synced = false;
  @override
  Future<List<SyncOutboxItem>> listPending() async => [item];
  @override
  Future<void> patch(String id, Map<String, Object?> values) async =>
      patches.add(values);
  @override
  Future<void> updateState(
    String id,
    SyncOutboxState state, {
    String? error,
    DateTime? nextRetryAt,
  }) async {
    lastState = state;
    lastError = error;
    this.nextRetryAt = nextRetryAt;
  }

  @override
  Future<void> markSynced(
    String id, {
    String? backendFileId,
    String? backendRecordId,
    String? uploadJobId,
  }) async {
    synced = true;
    lastState = SyncOutboxState.synced;
  }

  @override
  Future<void> retryAllFailed() async {}
  @override
  Future<void> create(SyncOutboxItem item) async {}
  @override
  Future<int> countFailed() async => 0;
  @override
  Future<int> countQueued() async => 0;
  @override
  Future<int> countProcessing() async => 0;
}

class _FakeRecords implements ShootingRecordRepository {
  _FakeRecords(this.record);
  final ShootingRecord record;
  @override
  Future<ShootingRecord?> getById(String id) async => record;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStages implements TcBackendUploadStages {
  _FakeStages({this.error, this.startGate});
  final TcBackendUploadException? error;
  final Completer<UploadStartResult>? startGate;
  int startCalls = 0, pollCalls = 0, recordCalls = 0;
  String? clientFileId;
  @override
  Future<UploadStartResult> startUpload(
    ShootingRecord record, {
    required String clientFileId,
  }) async {
    startCalls++;
    this.clientFileId = clientFileId;
    if (error != null) throw error!;
    return startGate?.future ?? const UploadStartResult(uploadJobId: 'job');
  }

  @override
  Future<UploadJobResult> pollUploadJob(String id) async {
    pollCalls++;
    if (error != null) throw error!;
    return UploadJobResult(
      uploadJobId: id,
      status: TcBackendUploadJobStatus.completed,
      backendFileId: 'file',
    );
  }

  @override
  Future<ObservationRecordResult> createObservationRecord(
    ShootingRecord record,
    String fileId,
  ) async {
    recordCalls++;
    if (error != null) throw error!;
    return const ObservationRecordResult(
      backendRecordId: 'remote-record',
      revision: 1,
    );
  }
}
