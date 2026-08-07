import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/features/settings/viewmodel/tc_backend_view_model.dart';
import 'package:astro_journal/features/settings/widgets/tc_backend_settings_section.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';

void main() {
  Future<TcBackendViewModel> viewModel({
    required bool enabled,
    required String baseUrl,
    int queued = 0,
    int processing = 0,
    int failed = 0,
    Future<void> Function()? retry,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = TcBackendSettingsService();
    await settings.save(TcBackendSettings(baseUrl: baseUrl, enabled: enabled));
    return TcBackendViewModel(
      settings,
      syncOutboxRepository: _FakeOutbox(queued, processing, failed),
      retryFailed: retry,
    );
  }

  Future<void> pump(WidgetTester tester, TcBackendViewModel vm) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: vm,
          child: const Scaffold(body: TcBackendSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('displays outbox counts and enables retry for failures', (
    tester,
  ) async {
    final vm = await viewModel(
      enabled: true,
      baseUrl: 'https://backend.example',
      queued: 3,
      processing: 2,
      failed: 1,
    );
    await pump(tester, vm);
    expect(find.text('대기중 3건'), findsOneWidget);
    expect(find.text('처리중 2건'), findsOneWidget);
    expect(find.text('실패 1건'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('sync_retry')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('retry button invokes retry and refreshes counts', (
    tester,
  ) async {
    var retries = 0;
    final vm = await viewModel(
      enabled: true,
      baseUrl: 'https://backend.example',
      failed: 1,
      retry: () async {
        retries++;
      },
    );
    await pump(tester, vm);
    await tester.tap(find.byKey(const Key('sync_retry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('shows disabled message for backend off or missing URL', (
    tester,
  ) async {
    final off = await viewModel(
      enabled: false,
      baseUrl: 'https://backend.example',
    );
    await pump(tester, off);
    expect(find.byKey(const Key('sync_backend_disabled')), findsOneWidget);
    final unset = await viewModel(enabled: false, baseUrl: '');
    await pump(tester, unset);
    expect(find.byKey(const Key('sync_backend_disabled')), findsOneWidget);
  });
}

class _FakeOutbox implements SyncOutboxRepository {
  _FakeOutbox(this.queued, this.processing, this.failed);
  final int queued;
  final int processing;
  final int failed;
  @override
  Future<int> countQueued() async => queued;
  @override
  Future<int> countProcessing() async => processing;
  @override
  Future<int> countFailed() async => failed;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
