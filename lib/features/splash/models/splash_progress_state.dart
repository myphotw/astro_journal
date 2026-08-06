import 'package:flutter/foundation.dart';

import 'startup_step.dart';

/// 스플래시 하단 진행 UI 상태 (하늘 애니메이션과 분리).
@immutable
class SplashProgressState {
  const SplashProgressState({
    required this.steps,
    required this.tagline,
    this.errorMessage,
  });

  final List<StartupStep> steps;
  final String tagline;
  final String? errorMessage;
}
