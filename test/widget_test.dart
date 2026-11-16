import 'package:flutter/foundation.dart';
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
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final homeTitle = isWindows ? '오늘 밤 촬영 도우미' : '천체 촬영 도우미';
    // 스플래시 레이아웃이 기본 테스트 뷰포트에서 미세 overflow 나지 않도록 확보.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const AstroJournalApp());
    // 스플래시가 끝나고 실제 내비게이션과 홈 제목이 표시될 때까지 대기한다.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('홈').evaluate().isNotEmpty &&
          find.text('사진 등록').evaluate().isNotEmpty &&
          find.text(homeTitle).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('사진 등록'), findsOneWidget);
    expect(find.text(homeTitle), findsOneWidget);

    // splash 최소 표시(~3.2s) + deferred warm-up Timer 소진.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(Duration.zero);
  });
}
