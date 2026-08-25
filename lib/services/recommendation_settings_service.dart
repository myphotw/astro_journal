import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/catalog_type.dart';
import '../core/constants/recommendation_priority_mode.dart';

/// 추천 대상 필터 설정 값 객체.
class RecommendationSettings {
  RecommendationSettings({
    required this.enabledCatalogs,
    required this.azimuthStart,
    required this.azimuthEnd,
    required this.minAltitude,
    required this.maxAltitude,
    this.priorityMode = RecommendationPriorityMode.uncapturedFirst,
  });

  /// 추천에 포함할 카탈로그 집합.
  final Set<CatalogType> enabledCatalogs;

  /// 관측 가능 방위각 시작 (0–359°).
  final int azimuthStart;

  /// 관측 가능 방위각 종료 (0–359°).
  final int azimuthEnd;

  /// 관측 가능 최소 고도 (°).
  final int minAltitude;

  /// 관측 가능 최대 고도 (°).
  final int maxAltitude;

  /// 추천 목록 정렬 우선순위.
  final RecommendationPriorityMode priorityMode;

  static RecommendationSettings get defaults => RecommendationSettings(
    enabledCatalogs: {
      CatalogType.messier,
      CatalogType.ngc,
      CatalogType.ic,
      CatalogType.sh2,
      CatalogType.caldwell,
      CatalogType.rcw,
      CatalogType.vdb,
      CatalogType.barnard,
      CatalogType.ldn,
      CatalogType.lbn,
    },
    azimuthStart: 0,
    azimuthEnd: 359,
    minAltitude: 0,
    maxAltitude: 90,
  );

  /// 방위각이 설정 범위 내에 있는지 확인 (300°→80° 같은 wrap-around 지원).
  bool isAzimuthInRange(double az) {
    final a = az % 360;
    if (azimuthStart <= azimuthEnd) {
      return a >= azimuthStart && a <= azimuthEnd;
    }
    return a >= azimuthStart || a <= azimuthEnd;
  }

  /// 고도가 설정 범위 내에 있는지 확인.
  bool isAltitudeInRange(double alt) =>
      alt >= minAltitude && alt <= maxAltitude;

  RecommendationSettings copyWith({
    Set<CatalogType>? enabledCatalogs,
    int? azimuthStart,
    int? azimuthEnd,
    int? minAltitude,
    int? maxAltitude,
    RecommendationPriorityMode? priorityMode,
  }) {
    return RecommendationSettings(
      enabledCatalogs: enabledCatalogs ?? Set.of(this.enabledCatalogs),
      azimuthStart: azimuthStart ?? this.azimuthStart,
      azimuthEnd: azimuthEnd ?? this.azimuthEnd,
      minAltitude: minAltitude ?? this.minAltitude,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      priorityMode: priorityMode ?? this.priorityMode,
    );
  }
}

/// 추천 대상 설정을 SharedPreferences에 저장/로드하는 서비스.
class RecommendationSettingsService {
  static const _keyCatalogs = 'rec_catalogs_v1';
  static const _keyPriorityMode = 'rec_priority_mode_v1';

  Future<RecommendationSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedList = prefs.getStringList(_keyCatalogs);
    final Set<CatalogType> catalogs;
    if (savedList == null) {
      catalogs = Set.of(RecommendationSettings.defaults.enabledCatalogs);
    } else {
      catalogs = savedList
          .map(
            (v) => CatalogType.values.firstWhere(
              (c) => c.value == v,
              orElse: () => CatalogType.messier,
            ),
          )
          .toSet();
    }

    return RecommendationSettings(
      enabledCatalogs: catalogs,
      // 관측 방향은 ActiveObservationSite/Horizon이 소유한다. 과거 전역
      // 방위각 설정은 읽지 않고 전체 범위를 안전한 호환값으로 사용한다.
      azimuthStart: 0,
      azimuthEnd: 359,
      // Site Horizon 연동 전에는 과거 전역 고도 제한을 적용하지 않는다.
      minAltitude: 0,
      maxAltitude: 90,
      priorityMode: RecommendationPriorityMode.fromStorageValue(
        prefs.getString(_keyPriorityMode),
      ),
    );
  }

  Future<void> save(RecommendationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyCatalogs,
      settings.enabledCatalogs.map((c) => c.value).toList(),
    );
    await prefs.setString(_keyPriorityMode, settings.priorityMode.storageValue);
  }
}
