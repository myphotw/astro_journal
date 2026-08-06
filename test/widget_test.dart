import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astro_journal/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const mapsChannel = MethodChannel('com.example.astro_journal/maps');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'write':
        case 'delete':
        case 'deleteAll':
          return null;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mapsChannel, (call) async {
      switch (call.method) {
        case 'syncGoogleMapsApiKey':
          return null;
        case 'getMapsApiKeyStatus':
          return {'configured': true, 'keyLength': 39};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mapsChannel, null);
  });

  testWidgets('앱이 홈 화면을 표시한다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    // 스플래시 레이아웃이 기본 테스트 뷰포트에서 미세 overflow 나지 않도록 확보.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AstroJournalApp());
    // 시작 preload + 최소 스플래시 표시 시간을 고려해 충분히 대기한다.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('천체 촬영 도우미').evaluate().isNotEmpty) break;
    }

    expect(find.text('천체 촬영 도우미'), findsOneWidget);
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('사진 등록'), findsOneWidget);

    // splash 최소 표시(~3.2s) + deferred warm-up Timer 소진.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(Duration.zero);
  });
}
