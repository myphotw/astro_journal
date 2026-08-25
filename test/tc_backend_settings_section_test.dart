import 'package:astro_journal/data/repositories/sync_outbox_repository.dart';
import 'package:astro_journal/features/settings/viewmodel/tc_backend_view_model.dart';
import 'package:astro_journal/features/settings/widgets/tc_backend_settings_section.dart';
import 'package:astro_journal/services/tc_backend_service.dart';
import 'package:astro_journal/services/tc_backend_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<TcBackendViewModel> viewModel({
    int queued = 0,
    int processing = 0,
    int failed = 0,
    Future<void> Function()? retry,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = TcBackendSettingsService();
    await settings.save(
      const TcBackendSettings(
        baseUrl: 'https://backend.example',
        enabled: true,
      ),
    );
    return TcBackendViewModel(
      settings,
      syncOutboxRepository: _FakeOutbox(queued, processing, failed),
      retryFailed: retry,
      serviceFactory: (_) => _healthyService(),
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

  testWidgets('shows readiness and outbox counts without credential fields', (
    tester,
  ) async {
    final vm = await viewModel(queued: 3, processing: 2, failed: 1);
    await pump(tester, vm);

    expect(find.byKey(const Key('backend_readiness')), findsOneWidget);
    expect(find.text('NAS 서버'), findsOneWidget);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('위치 검색'), findsOneWidget);
    expect(find.text('Plate Solve'), findsOneWidget);
    expect(find.text('Vision'), findsNothing);
    expect(find.text('대기중 3건'), findsOneWidget);
    expect(find.text('처리중 2건'), findsOneWidget);
    expect(find.text('실패 1건'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('retry button invokes retry', (tester) async {
    var retries = 0;
    final vm = await viewModel(failed: 1, retry: () async => retries++);
    await pump(tester, vm);
    await tester.tap(find.byKey(const Key('sync_retry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('refresh reloads readiness and sync counts', (tester) async {
    final vm = await viewModel();
    await pump(tester, vm);
    await tester.tap(find.byKey(const Key('backend_status_refresh')));
    await tester.pumpAndSettle();
    expect(vm.result?.isCompatible, isTrue);
  });
}

TcBackendService _healthyService() => TcBackendService(
  baseUrl: 'https://backend.example',
  client: MockClient((request) async {
    if (request.url.path.endsWith('/health')) {
      return http.Response('{"status":"ok"}', 200);
    }
    if (request.url.path.endsWith('/capabilities')) {
      return http.Response(
        '{"supported_services":["AstroJournal"],"upload_contract":{"supports_service_name":true,"supports_client_file_id":true}}',
        200,
      );
    }
    return http.Response(
      '{"services":{"weather":{"configured":true},"google_geocoding":{"configured":true},"google_places":{"configured":true},"astrometry":{"configured":true}},"vision":true}',
      200,
    );
  }),
);

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
