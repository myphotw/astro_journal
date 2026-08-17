import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/data/models/backend_upload_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/models/sync_outbox_item.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:astro_journal/services/tc_backend_record_service.dart';
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
    Map<String, dynamic> payload = const {},
  }) => SyncOutboxItem(
    operationId: 'operation',
    localRecordId: record.id,
    clientFileId: 'stable-client-id',
    clientRecordId: 'client-record-id',
    payload: payload,
    state: state,
    uploadJobId: jobId,
    backendFileId: fileId,
    backendRecordId: recordId,
    retryCount: retryCount,
    nextRetryAt: retryAt,
    lastError: error,
  );

  SyncOutboxItem mutationItem(
    SyncOperationType type, {
    SyncOutboxState state = SyncOutboxState.queued,
    Map<String, dynamic> payload = const {},
  }) => SyncOutboxItem(
    operationId: 'mutation-operation',
    operationType: type,
    backendRecordId: 'remote-record',
    payload: payload,
    state: state,
  );

  test('common_file_id survives the Outbox payload JSON round trip', () {
    final map = item(payload: const {'common_file_id': 178}).toMap();
    map['id'] = 1;

    final restored = SyncOutboxItem.fromMap(map);

    expect(restored.payload['common_file_id'], 178);
    expect(restored.payload['common_file_id'], isA<int>());
  });

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
    expect(upload.commonFileId, 178);
    expect(outbox.markedBackendFileId, 'file');
    expect(
      outbox.patches.any(
        (patch) =>
            patch['payload_json'] is String &&
            (patch['payload_json'] as String).contains('"common_file_id":178'),
      ),
      isTrue,
    );
    expect(outbox.synced, isTrue);
  });

  test(
    'app restart restores common_file_id without upload or polling',
    () async {
      final outbox = _FakeOutbox(
        item(
          state: SyncOutboxState.recordCreating,
          jobId: 'job',
          fileId: 'logical-file',
          payload: const {'common_file_id': 178},
        ),
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
      expect(upload.commonFileId, 178);
    },
  );

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
    final outbox = _FakeOutbox(
      item(
        payload: const {
          'observation_date': '2026-08-17',
          'canonical_target_id': 'M42',
          'target_display_name': 'Orion Nebula',
        },
      ),
    );
    final upload = _FakeStages();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();
    expect(upload.clientFileId, 'stable-client-id');
    expect(upload.clientRecordId, 'client-record-id');
    expect(upload.metadata?.toFields(), {
      'observation_date': '2026-08-17',
      'canonical_target_id': 'M42',
      'target_display_name': 'Orion Nebula',
    });
  });

  test('record POST replay preserves durable client_record_id', () async {
    final stages = _ReplayRecordStages();
    for (var attempt = 0; attempt < 2; attempt++) {
      await TcBackendSyncCoordinator(
        _FakeOutbox(
          item(
            state: SyncOutboxState.recordCreating,
            fileId: 'logical-file',
            payload: const {'common_file_id': 178},
          ),
        ),
        _FakeRecords(record),
        settings,
        stages,
      ).drain();
    }

    expect(stages.clientRecordIds, ['client-record-id', 'client-record-id']);
    expect(stages.commonFileIds, [178, 178]);
  });

  test('missing common_file_id never sends an ObservationRecord', () async {
    final outbox = _FakeOutbox(
      item(state: SyncOutboxState.recordCreating, fileId: 'logical-file'),
    );
    final upload = _FakeStages();

    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      upload,
    ).drain();

    expect(upload.recordCalls, 0);
    expect(outbox.lastState, SyncOutboxState.failed);
    expect(outbox.lastError, startsWith('malformedResponse|'));
  });

  test('PATCH resumes, stores revision, and marks outbox synced', () async {
    final outbox = _FakeOutbox(
      mutationItem(
        SyncOperationType.recordPatch,
        state: SyncOutboxState.processing,
        payload: const {'revision': 3, 'favorite': true},
      ),
    );
    final records = _FakeRecordMutations();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      _FakeStages(),
      recordService: records,
    ).drain();

    expect(records.patchCalls, 1);
    expect(records.lastRevision, 3);
    expect(records.lastFields, {'favorite': true});
    expect(outbox.synced, isTrue);
    expect(
      outbox.patches.any(
        (patch) =>
            patch['payload_json'] is String &&
            (patch['payload_json'] as String).contains('"revision":4'),
      ),
      isTrue,
    );
  });

  test('DELETE resumes idempotently and marks outbox synced', () async {
    final outbox = _FakeOutbox(mutationItem(SyncOperationType.recordDelete));
    final records = _FakeRecordMutations();
    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      _FakeStages(),
      recordService: records,
    ).drain();

    expect(records.deleteCalls, 1);
    expect(outbox.synced, isTrue);
  });

  test('Backend OFF leaves mutation queued without an HTTP call', () async {
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: false,
      ),
    );
    final outbox = _FakeOutbox(
      mutationItem(
        SyncOperationType.recordPatch,
        payload: const {'revision': 3, 'favorite': true},
      ),
    );
    final records = _FakeRecordMutations();

    await TcBackendSyncCoordinator(
      outbox,
      _FakeRecords(record),
      settings,
      _FakeStages(),
      recordService: records,
    ).drain();

    expect(records.patchCalls, 0);
    expect(outbox.lastState, isNull);
    expect(outbox.synced, isFalse);
  });

  test('mutation 5xx retries while 409 durably stores conflict', () async {
    for (final scenario in <TcBackendRecordException>[
      const TcBackendRecordException(
        BackendUploadErrorType.http5xx,
        'temporary',
      ),
      const TcBackendRecordException(
        BackendUploadErrorType.http409,
        'conflict',
        statusCode: 409,
        currentRevision: 9,
      ),
    ]) {
      final outbox = _FakeOutbox(
        mutationItem(
          SyncOperationType.recordPatch,
          payload: const {'revision': 3, 'memo': 'local'},
        ),
      );
      await TcBackendSyncCoordinator(
        outbox,
        _FakeRecords(record),
        settings,
        _FakeStages(),
        recordService: _FakeRecordMutations(error: scenario),
        now: () => DateTime.utc(2026),
      ).drain();

      expect(outbox.lastState, SyncOutboxState.failed);
      expect(
        outbox.nextRetryAt != null,
        scenario.type == BackendUploadErrorType.http5xx,
      );
      if (scenario.type == BackendUploadErrorType.http409) {
        expect(outbox.lastError, contains('current_revision=9'));
        expect(
          outbox.patches.any(
            (patch) =>
                patch['payload_json'] is String &&
                (patch['payload_json'] as String).contains(
                  '"current_revision":9',
                ),
          ),
          isTrue,
        );
      }
    }
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
  String? markedBackendFileId;
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
    markedBackendFileId = backendFileId;
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
  @override
  Future<void> enqueueRecordPatch({
    required String backendRecordId,
    required int expectedRevision,
    required Map<String, Object?> fields,
    String? localRecordId,
  }) async {}
  @override
  Future<void> enqueueRecordDelete({
    required String backendRecordId,
    String? localRecordId,
  }) async {}
  @override
  Future<void> cancelPendingUpload(String localRecordId) async {}
  @override
  Future<void> rebaseQueuedRecordPatches(
    String backendRecordId,
    int revision,
  ) async {}
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
  String? clientRecordId;
  int? commonFileId;
  TcBackendUploadMetadata? metadata;
  @override
  Future<UploadStartResult> startUpload(
    ShootingRecord record, {
    required String clientFileId,
    TcBackendUploadMetadata? metadata,
  }) async {
    startCalls++;
    this.clientFileId = clientFileId;
    this.metadata = metadata;
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
      commonFileId: 178,
    );
  }

  @override
  Future<ObservationRecordResult> createObservationRecord(
    ShootingRecord record,
    int commonFileId, {
    String? clientRecordId,
  }) async {
    recordCalls++;
    this.clientRecordId = clientRecordId;
    this.commonFileId = commonFileId;
    if (error != null) throw error!;
    return const ObservationRecordResult(
      backendRecordId: 'remote-record',
      revision: 1,
    );
  }
}

class _FakeRecordMutations implements TcBackendRecordMutations {
  _FakeRecordMutations({this.error});

  final TcBackendRecordException? error;
  int patchCalls = 0;
  int deleteCalls = 0;
  int? lastRevision;
  Map<String, Object?>? lastFields;

  @override
  Future<TcBackendRecordPatchResult> patchRecord(
    String recordId,
    int revision,
    Map<String, Object?> partialFields,
  ) async {
    patchCalls++;
    lastRevision = revision;
    lastFields = partialFields;
    if (error != null) throw error!;
    return const TcBackendRecordPatchResult(
      recordId: 'remote-record',
      revision: 4,
      canonicalFields: {'favorite': true},
    );
  }

  @override
  Future<TcBackendRecordDeleteResult> deleteRecord(String recordId) async {
    deleteCalls++;
    if (error != null) throw error!;
    return TcBackendRecordDeleteResult(
      recordId: recordId,
      revision: 4,
      deletedAt: DateTime.utc(2026),
    );
  }
}

class _ReplayRecordStages implements TcBackendUploadStages {
  final List<String?> clientRecordIds = [];
  final List<int> commonFileIds = [];

  @override
  Future<ObservationRecordResult> createObservationRecord(
    ShootingRecord record,
    int commonFileId, {
    String? clientRecordId,
  }) async {
    clientRecordIds.add(clientRecordId);
    commonFileIds.add(commonFileId);
    if (clientRecordIds.length == 1) {
      throw const TcBackendUploadException(
        BackendUploadErrorType.network,
        'response lost',
      );
    }
    return const ObservationRecordResult(
      backendRecordId: 'same-server-record',
      revision: 1,
    );
  }

  @override
  Future<UploadJobResult> pollUploadJob(String uploadJobId) =>
      throw StateError('poll must not run');

  @override
  Future<UploadStartResult> startUpload(
    ShootingRecord record, {
    required String clientFileId,
    TcBackendUploadMetadata? metadata,
  }) => throw StateError('upload must not run');
}
