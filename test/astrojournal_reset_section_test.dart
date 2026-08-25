import 'package:astro_journal/data/models/astrojournal_reset.dart';
import 'package:astro_journal/features/settings/viewmodel/settings_view_model.dart';
import 'package:astro_journal/features/settings/widgets/astrojournal_reset_section.dart';
import 'package:astro_journal/services/astrojournal_capture_reset_coordinator.dart';
import 'package:astro_journal/services/astrojournal_local_capture_reset_service.dart';
import 'package:astro_journal/services/backup_service.dart';
import 'package:astro_journal/services/tc_backend_astrojournal_reset_service.dart';
import 'package:astro_journal/services/tc_backend_sync_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'preview explains physical deletion, preservation, and confirmation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _FakeApi();
      final local = _FakeLocalReset();
      var completed = 0;
      await _pump(
        tester,
        api: api,
        local: local,
        onCompleted: () => completed++,
      );

      await tester.tap(find.text('촬영 데이터 초기화'));
      await tester.pumpAndSettle();

      expect(api.previewCalls, 1);
      expect(find.text('127개'), findsOneWidget);
      expect(find.text('84장'), findsOneWidget);
      expect(find.text('80장'), findsOneWidget);
      expect(find.text('4장'), findsOneWidget);
      expect(find.textContaining('NAS에서도 삭제됩니다'), findsOneWidget);
      expect(find.textContaining('공유 사진은 삭제되지 않습니다'), findsOneWidget);
      expect(
        find.textContaining('장비 · 관측지 · Horizon · Catalog · 앱 설정'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('reset-preview-continue')));
      await tester.pumpAndSettle();
      FilledButton executeButton() => tester.widget<FilledButton>(
        find.byKey(const Key('reset-execute-button')),
      );
      expect(executeButton().onPressed, isNull);
      expect(api.executeCalls, 0);

      await tester.enterText(
        find.byKey(const Key('reset-confirmation-field')),
        '삭제',
      );
      await tester.pump();
      expect(executeButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('reset-confirmation-field')),
        '초기화',
      );
      await tester.pump();
      expect(executeButton().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('reset-execute-button')));
      await tester.pumpAndSettle();

      expect(api.executeCalls, 1);
      expect(local.calls, 1);
      expect(local.cursor, '912');
      expect(find.text('촬영 데이터 초기화 완료'), findsOneWidget);
      expect(find.textContaining('장비와 관측지 설정은 그대로 유지됩니다'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(completed, 1);
    },
  );

  testWidgets('execute 409 shows friendly message and keeps local data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeApi()
      ..executeError = const AstroJournalResetException(
        type: AstroJournalResetErrorType.blocked,
        message: 'ASTROJOURNAL_RESET_BLOCKED',
        statusCode: 409,
      );
    final local = _FakeLocalReset();
    await _pump(tester, api: api, local: local);

    await tester.tap(find.text('촬영 데이터 초기화'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-preview-continue')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reset-confirmation-field')),
      '초기화',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reset-execute-button')));
    await tester.pumpAndSettle();

    expect(local.calls, 0);
    expect(find.text('초기화 대기 필요'), findsOneWidget);
    expect(find.textContaining('사진 처리 작업이 진행 중입니다'), findsOneWidget);
    expect(find.textContaining('ASTROJOURNAL_RESET_BLOCKED'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  required _FakeLocalReset local,
  VoidCallback? onCompleted,
}) async {
  final viewModel = SettingsViewModel(
    AstroJournalCaptureResetCoordinator(api, local, TcBackendSyncGate()),
    BackupService(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider.value(
          value: viewModel,
          child: AstroJournalResetSection(onCompleted: onCompleted),
        ),
      ),
    ),
  );
}

class _FakeApi implements AstroJournalResetApi {
  int previewCalls = 0;
  int executeCalls = 0;
  Object? executeError;

  @override
  Future<AstroJournalResetPreview> preview() async {
    previewCalls++;
    return _preview;
  }

  @override
  Future<AstroJournalResetResult> execute() async {
    executeCalls++;
    if (executeError case final error?) throw error;
    return _result;
  }
}

class _FakeLocalReset implements AstroJournalLocalCaptureReset {
  int calls = 0;
  String? cursor;

  @override
  Future<void> clearCaptureData({String? resetEventCursor}) async {
    calls++;
    cursor = resetEventCursor;
  }
}

const _preview = AstroJournalResetPreview(
  observationRecordCount: 127,
  astroFileCount: 84,
  astroOnlyFileCount: 80,
  sharedFileCount: 4,
  plateSolveResultCount: 0,
  photoObjectCount: 0,
  uploadJobCount: 2,
  pendingUploadCount: 1,
  processingUploadCount: 0,
  processingVisionJobCount: 0,
  processingJobCount: 0,
  physicalOriginalDeleteCount: 80,
  physicalPreviewDeleteCount: 80,
  physicalThumbnailDeleteCount: 80,
  preservedSharedFileCount: 4,
  resetBlocked: false,
);

const _result = AstroJournalResetResult(
  resetCompleted: true,
  deletedObservationRecordCount: 127,
  removedAstroFileLinkCount: 84,
  tombstonedCommonFileCount: 80,
  preservedSharedFileCount: 4,
  deletedUploadJobCount: 2,
  deletedOriginalCount: 80,
  deletedPreviewCount: 80,
  deletedThumbnailCount: 80,
  deletedPlateSolveResultCount: 0,
  deletedPhotoObjectCount: 0,
  resetEventCursor: 912,
);
