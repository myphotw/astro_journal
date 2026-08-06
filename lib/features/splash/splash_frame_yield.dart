import 'package:flutter/scheduler.dart';

/// 스플래시 애니메이션 프레임이 그려질 때까지 양보한다.
Future<void> yieldForSplashAnimation() async {
  await Future<void>.delayed(Duration.zero);
  await SchedulerBinding.instance.endOfFrame;
  // 한 프레임만으로는 긴 CPU 청크 직후 티커가 따라잡지 못하는 경우가 있어
  // 한 번 더 양보한다.
  await Future<void>.delayed(Duration.zero);
  await SchedulerBinding.instance.endOfFrame;
}
