import 'package:flutter/material.dart';

import '../../../core/navigation/app_navigation_notifier.dart';
import '../../../core/navigation/double_back_exit_controller.dart';

/// [MainShell] 뒤로가기 처리 결과.
enum MainBackAction {
  /// 현재 탭 Nested Navigator에서 pop 수행됨.
  poppedNested,

  /// 홈 탭으로 이동 (다른 탭 루트).
  navigateHome,

  /// 종료 안내 SnackBar 표시 (홈 루트, 첫 입력).
  showExitHint,

  /// 앱 종료.
  exitApp,

  /// 처리 없음.
  none,
}

/// 메인 셸 뒤로가기 판단 — 종료는 홈 탭 루트에서만 적용한다.
class MainBackNavigationViewModel extends ChangeNotifier {
  MainBackNavigationViewModel(this._navigationNotifier);

  final AppNavigationNotifier _navigationNotifier;
  final DoubleBackExitController _exitController = DoubleBackExitController();

  static const String exitHintMessage =
      '한 번 더 누르면 앱이 종료됩니다.';

  int get homeTabIndex => 0;

  /// 시스템/AppBar 뒤로가기 공통 처리.
  MainBackAction handleBackRequest({
    required int currentTabIndex,
    required List<GlobalKey<NavigatorState>> navigatorKeys,
    required bool didPop,
  }) {
    if (didPop) return MainBackAction.none;

    final navigator = navigatorKeys[currentTabIndex].currentState;
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      return MainBackAction.poppedNested;
    }

    if (currentTabIndex != homeTabIndex) {
      resetExitState();
      _navigationNotifier.navigateTo(homeTabIndex);
      return MainBackAction.navigateHome;
    }

    if (_exitController.shouldExitOnBack()) {
      return MainBackAction.exitApp;
    }

    return MainBackAction.showExitHint;
  }

  void resetExitState() => _exitController.reset();

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }
}
