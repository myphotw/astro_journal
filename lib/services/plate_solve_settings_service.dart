import 'package:shared_preferences/shared_preferences.dart';

/// Plate Solve 관련 사용자 설정.
class PlateSolveSettings {
  const PlateSolveSettings({
    required this.astrometryEnabled,
    required this.autoSolveOnRegister,
  });

  /// Astrometry.net API 활성화 여부 (관리자 API 관리 화면의 On/Off).
  final bool astrometryEnabled;

  /// 하위 호환용 필드. 등록 시 자동 실행은 더 이상 사용하지 않는다.
  final bool autoSolveOnRegister;

  static const defaults = PlateSolveSettings(
    astrometryEnabled: true,
    autoSolveOnRegister: false,
  );

  PlateSolveSettings copyWith({
    bool? astrometryEnabled,
    bool? autoSolveOnRegister,
  }) {
    return PlateSolveSettings(
      astrometryEnabled: astrometryEnabled ?? this.astrometryEnabled,
      autoSolveOnRegister: autoSolveOnRegister ?? this.autoSolveOnRegister,
    );
  }
}

/// Plate Solve 설정을 SharedPreferences에 저장/로드한다.
class PlateSolveSettingsService {
  static const _keyAstrometryEnabled = 'plate_solve_astrometry_enabled_v1';
  static const _keyAutoSolveOnRegister = 'plate_solve_auto_run_v1';

  Future<PlateSolveSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlateSolveSettings(
      astrometryEnabled: prefs.getBool(_keyAstrometryEnabled) ?? true,
      autoSolveOnRegister: prefs.getBool(_keyAutoSolveOnRegister) ?? false,
    );
  }

  Future<void> save(PlateSolveSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAstrometryEnabled, settings.astrometryEnabled);
    await prefs.setBool(_keyAutoSolveOnRegister, settings.autoSolveOnRegister);
  }
}
