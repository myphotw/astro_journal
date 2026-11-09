import 'package:astro_journal/data/models/tc_backend_models.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/view/gallery_screen.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/gallery_incremental_refresh_service.dart';
import 'package:astro_journal/services/tc_backend_connection_manager.dart';
import 'package:astro_journal/services/tc_backend_sync_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Connection extends Fake implements TcBackendConnectionManager {
  _Connection(this.currentStatus);

  TcBackendConnectionStatus currentStatus;
  int reconnects = 0;

  @override
  TcBackendConnectionStatus get status => currentStatus;

  @override
  Future<void> reconnect() async {
    reconnects++;
  }
}

class _Pull implements TcBackendDrainRunner {
  int calls = 0;

  @override
  Future<void> drain() async {
    calls++;
  }
}

class _Records extends Fake implements ShootingRecordRepository {}

class _Catalog extends Fake implements CatalogRepository {}

Future<void> _show(
  WidgetTester tester,
  _Connection connection,
  _Pull pull,
) async {
  final gallery = GalleryViewModel(
    _Records(),
    _Catalog(),
    CatalogSearchService(),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GalleryViewModel>.value(value: gallery),
        InheritedProvider<TcBackendConnectionManager>.value(value: connection),
        Provider<GalleryIncrementalRefreshService>.value(
          value: GalleryIncrementalRefreshService(
            pull: pull,
            connection: connection,
          ),
        ),
      ],
      child: const MaterialApp(home: GalleryScreen()),
    ),
  );
}

void main() {
  testWidgets('manual gallery refresh reconnects and runs incremental pull', (
    tester,
  ) async {
    final connection = _Connection(TcBackendConnectionStatus.connected);
    final pull = _Pull();
    await _show(tester, connection, pull);

    await tester.tap(find.byTooltip('새 사진 확인'));
    await tester.pump();
    await tester.pump();

    expect(connection.reconnects, 1);
    expect(pull.calls, 1);
    expect(find.text('새 사진 확인을 완료했습니다.'), findsOneWidget);
  });

  testWidgets('manual refresh reports offline without removing gallery', (
    tester,
  ) async {
    final connection = _Connection(TcBackendConnectionStatus.notConfigured);
    final pull = _Pull();
    await _show(tester, connection, pull);

    await tester.tap(find.byTooltip('새 사진 확인'));
    await tester.pump();
    await tester.pump();

    expect(pull.calls, 0);
    expect(find.text('서버에 연결할 수 없습니다. 저장된 사진은 계속 볼 수 있습니다.'), findsOneWidget);
    expect(find.text('갤러리'), findsOneWidget);
  });
}
