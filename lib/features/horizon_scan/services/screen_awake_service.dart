import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract interface class ScreenAwakeService {
  Future<void> enable();

  Future<void> disable();
}

class MobileScreenAwakeService implements ScreenAwakeService {
  const MobileScreenAwakeService();

  bool get _isSupportedMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> enable() => _isSupportedMobilePlatform
      ? WakelockPlus.enable()
      : Future<void>.value();

  @override
  Future<void> disable() => _isSupportedMobilePlatform
      ? WakelockPlus.disable()
      : Future<void>.value();
}
