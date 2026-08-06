import 'package:astro_journal/core/navigation/app_navigation_notifier.dart';
import 'package:astro_journal/features/main/viewmodel/main_back_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MainBackNavigationViewModel', () {
    late AppNavigationNotifier navigationNotifier;
    late MainBackNavigationViewModel viewModel;
    late GlobalKey<NavigatorState> homeNavKey;

    setUp(() {
      navigationNotifier = AppNavigationNotifier();
      viewModel = MainBackNavigationViewModel(navigationNotifier);
      homeNavKey = GlobalKey<NavigatorState>();
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('홈 루트 첫 뒤로가기는 종료 안내', () {
      final action = viewModel.handleBackRequest(
        currentTabIndex: 0,
        navigatorKeys: [homeNavKey],
        didPop: false,
      );
      expect(action, MainBackAction.showExitHint);
    });

    test('홈 루트 2초 이내 두 번째는 앱 종료', () {
      viewModel.handleBackRequest(
        currentTabIndex: 0,
        navigatorKeys: [homeNavKey],
        didPop: false,
      );
      final action = viewModel.handleBackRequest(
        currentTabIndex: 0,
        navigatorKeys: [homeNavKey],
        didPop: false,
      );
      expect(action, MainBackAction.exitApp);
    });

    test('다른 탭 루트는 홈으로 이동하고 종료하지 않는다', () {
      navigationNotifier.navigateTo(2);

      final action = viewModel.handleBackRequest(
        currentTabIndex: 2,
        navigatorKeys: [GlobalKey<NavigatorState>(), GlobalKey(), homeNavKey],
        didPop: false,
      );

      expect(action, MainBackAction.navigateHome);
      expect(navigationNotifier.currentIndex, 0);
    });

    testWidgets('nested Navigator pop 가능하면 pop 처리', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: homeNavKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('root')),
            ),
          ),
        ),
      );

      homeNavKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(homeNavKey.currentState!.canPop(), isTrue);

      final action = viewModel.handleBackRequest(
        currentTabIndex: 0,
        navigatorKeys: [homeNavKey],
        didPop: false,
      );

      expect(action, MainBackAction.poppedNested);
      expect(homeNavKey.currentState!.canPop(), isFalse);
    });
  });
}
