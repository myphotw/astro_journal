import 'dart:async';

/// 홈(루트) 화면에서 뒤로가기 두 번으로 앱 종료를 처리한다.
class DoubleBackExitController {
  DoubleBackExitController({
    this.confirmDuration = const Duration(seconds: 2),
  });

  static const String defaultMessage = '한 번 더 누르면 앱이 종료됩니다.';

  final Duration confirmDuration;

  DateTime? _lastAttempt;
  Timer? _resetTimer;

  /// 첫 입력이면 `false`(종료 안 함), 확인 시간 내 두 번째면 `true`(종료).
  bool shouldExitOnBack() {
    final now = DateTime.now();

    if (_lastAttempt != null &&
        now.difference(_lastAttempt!) < confirmDuration) {
      reset();
      return true;
    }

    _lastAttempt = now;
    _resetTimer?.cancel();
    _resetTimer = Timer(confirmDuration, reset);
    return false;
  }

  void reset() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _lastAttempt = null;
  }

  void dispose() {
    reset();
  }
}
