import 'package:shared_preferences/shared_preferences.dart';

/// 카탈로그 기본 촬영시간 계산에 사용하는 기준 Bortle 등급 설정.
class BaseExposureSettings {
  const BaseExposureSettings({required this.referenceBortle});

  /// 카탈로그 기본 촬영시간 계산 기준 Bortle (1–9).
  final int referenceBortle;

  static const int defaultReferenceBortle = 8;

  static BaseExposureSettings get defaults =>
      const BaseExposureSettings(referenceBortle: defaultReferenceBortle);
}

/// 기준 Bortle 설정을 SharedPreferences에 저장/로드한다.
class BaseExposureSettingsService {
  static const _keyReferenceBortle = 'base_exposure_reference_bortle_v1';

  Future<BaseExposureSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final bortle =
        prefs.getInt(_keyReferenceBortle) ??
        BaseExposureSettings.defaultReferenceBortle;
    return BaseExposureSettings(
      referenceBortle: bortle.clamp(1, 9),
    );
  }

  Future<void> save(BaseExposureSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyReferenceBortle,
      settings.referenceBortle.clamp(1, 9),
    );
  }
}
