/// 카탈로그 ID별 크기·설명 정적 메타데이터.
class CatalogMetadataEntry {
  const CatalogMetadataEntry({
    this.angularSize,
    this.representativeFramingSize,
    this.description,
  });

  /// Catalog 표시·DB 저장용 각경.
  final String? angularSize;

  /// 장비 추천 전용 대표 프레이밍 (가로 × 세로). Catalog와 독립.
  final String? representativeFramingSize;
  final String? description;
}

abstract final class CatalogObjectMetadataOverrides {
  static CatalogMetadataEntry? forId(String id) =>
      _entries[id] ?? _entries[id.toUpperCase()];

  /// 장비 추천용 대표 프레이밍 문자열 (Catalog angular_size와 분리).
  static String? representativeFramingOverrideForId(String id) {
    final entry = forId(id);
    if (entry?.representativeFramingSize != null) {
      return entry!.representativeFramingSize;
    }
    return _representativeFramingOverrides[id] ??
        _representativeFramingOverrides[id.toUpperCase()];
  }

  static const _representativeFramingOverrides = <String, String>{
    'M8': "90' × 40'",
    'M16': "65' × 50'",
    'M17': "25' × 20'",
    'M20': "35' × 30'",
    'M31': "190' × 60'",
    'M33': "73' × 45'",
    'M42': "85' × 60'",
    'M45': "120' × 80'",
    'NGC 2237': "80' × 60'",
    'NGC 7000': "120' × 100'",
    'IC 1396': "170' × 140'",
    'NGC 6960': "60' × 8'",
    'NGC 1499': "120' × 35'",
    'NGC1499': "120' × 35'",
  };

  /// 대표 프레이밍 주축의 시위각(°), 북→동.
  static double? positionAngleDegreesForId(String id) =>
      _positionAngleDegrees[id] ?? _positionAngleDegrees[id.toUpperCase()];

  static const _positionAngleDegrees = <String, double>{
    'M31': 35,
    'M33': 23,
    'M51': 170,
    'M101': 90,
    'NGC 1499': 90,
    'NGC1499': 90,
  };

  static const _entries = <String, CatalogMetadataEntry>{
    'M1': CatalogMetadataEntry(angularSize: "6' × 4'", description: '황소자리의 초신성잔해. 펄서 구름.'),
    'M2': CatalogMetadataEntry(angularSize: "16'", description: '물병자리의 구상성단.'),
    'M3': CatalogMetadataEntry(angularSize: "18'", description: '사냥개자리의 구상성단.'),
    'M4': CatalogMetadataEntry(angularSize: "36'", description: '전갈자리의 구상성단. 육안으로도 관측 가능.'),
    'M5': CatalogMetadataEntry(angularSize: "23'", description: '뱀자리의 구상성단.'),
    'M6': CatalogMetadataEntry(angularSize: "25'", description: '전갈자리의 산개성단. 나비 성단.'),
    'M7': CatalogMetadataEntry(angularSize: "80'", description: '전갈자리의 산개성단. 육안으로도 선명.'),
    'M8': CatalogMetadataEntry(angularSize: "90' × 40'", description: '궁수자리의 발광성운. 석호 성운.'),
    'M9': CatalogMetadataEntry(angularSize: "9'", description: '뱀자리의 구상성단.'),
    'M10': CatalogMetadataEntry(angularSize: "20'", description: '독소자리의 구상성단.'),
    'M11': CatalogMetadataEntry(angularSize: "14'", description: '방패자리의 산개성단. 야생오리 성단.'),
    'M12': CatalogMetadataEntry(angularSize: "16'", description: '독소자리의 구상성단.'),
    'M13': CatalogMetadataEntry(angularSize: "20'", description: '헤라클레스자리의 구상성단. 북반구 대표 구상성단.'),
    'M14': CatalogMetadataEntry(angularSize: "11'", description: '독소자리의 구상성단.'),
    'M15': CatalogMetadataEntry(angularSize: "18'", description: '술자리의 구상성단.'),
    'M16': CatalogMetadataEntry(angularSize: "7'", description: '독수리자리의 발광성운. 이글 성운.'),
    'M17': CatalogMetadataEntry(angularSize: "11'", description: '궁수자리의 발광성운. 오메가 성운.'),
    'M18': CatalogMetadataEntry(angularSize: "9'", description: '궁수자리의 산개성단.'),
    'M19': CatalogMetadataEntry(angularSize: "17'", description: '뱀자리의 구상성단.'),
    'M20': CatalogMetadataEntry(angularSize: "28'", description: '궁수자리의 삼열성운.'),
    'M21': CatalogMetadataEntry(angularSize: "13'", description: '궁수자리의 산개성단.'),
    'M22': CatalogMetadataEntry(angularSize: "32'", description: '궁수자리의 구상성단.'),
    'M23': CatalogMetadataEntry(angularSize: "27'", description: '궁수자리의 산개성단.'),
    'M24': CatalogMetadataEntry(angularSize: "90'", description: '궁수자리의 별무리.'),
    'M25': CatalogMetadataEntry(angularSize: "32'", description: '궁수자리의 산개성단.'),
    'M26': CatalogMetadataEntry(angularSize: "15'", description: '방패자리의 산개성단.'),
    'M27': CatalogMetadataEntry(angularSize: "8' × 6'", description: '여우자리의 행성상성운. 아령 성운.'),
    'M28': CatalogMetadataEntry(angularSize: "18'", description: '궁수자리의 구상성단.'),
    'M29': CatalogMetadataEntry(angularSize: "7'", description: '백조자리의 산개성단.'),
    'M30': CatalogMetadataEntry(angularSize: "12'", description: '염소자리의 구상성단.'),
    'M31': CatalogMetadataEntry(angularSize: "190' × 60'", description: '안드로메다자리의 나선은하. 북반구 최대 은하.'),
    'M32': CatalogMetadataEntry(angularSize: "8' × 6'", description: '안드로메다 은하의 위성은하.'),
    'M33': CatalogMetadataEntry(angularSize: "73' × 45'", description: '삼각자리의 나선은하.'),
    'M34': CatalogMetadataEntry(angularSize: "35'", description: '페르세우스자리의 산개성단.'),
    'M35': CatalogMetadataEntry(angularSize: "28'", description: '쌍둥이자리의 산개성단.'),
    'M36': CatalogMetadataEntry(angularSize: "12'", description: '마차부자리의 산개성단.'),
    'M37': CatalogMetadataEntry(angularSize: "24'", description: '마차부자리의 산개성단.'),
    'M38': CatalogMetadataEntry(angularSize: "21'", description: '마차부자리의 산개성단.'),
    'M39': CatalogMetadataEntry(angularSize: "32'", description: '백조자리의 산개성단.'),
    'M40': CatalogMetadataEntry(angularSize: "0.8'", description: '쌍둥이자리의 쌍성. 윈넥 4.'),
    'M41': CatalogMetadataEntry(angularSize: "38'", description: '큰개자리의 산개성단.'),
    'M42': CatalogMetadataEntry(angularSize: "85' × 60'", description: '오리온자리의 발광성운. 북반구 대표 딥스카이.'),
    'M43': CatalogMetadataEntry(angularSize: "20' × 15'", description: '오리온자리의 발광성운. M42 인근.'),
    'M44': CatalogMetadataEntry(angularSize: "95'", description: '게자리의 산개성단. 벌집 성단.'),
    'M45': CatalogMetadataEntry(angularSize: "110'", description: '황소자리의 산개성단. 플레이아데스.'),
    'M46': CatalogMetadataEntry(angularSize: "27'", description: '고물자리의 산개성단.'),
    'M47': CatalogMetadataEntry(angularSize: "30'", description: '고물자리의 산개성단.'),
    'M48': CatalogMetadataEntry(angularSize: "30'", description: '바다뱀자리의 산개성단.'),
    'M49': CatalogMetadataEntry(angularSize: "10' × 8'", description: '처녀자리의 타원은하.'),
    'M50': CatalogMetadataEntry(angularSize: "16'", description: '뱀자리의 산개성단.'),
    'M51': CatalogMetadataEntry(angularSize: "11' × 7'", description: '사냥개자리의 나선은하. Whirlpool Galaxy.'),
    'M52': CatalogMetadataEntry(angularSize: "13'", description: '카시오페ia자리의 산개성단.'),
    'M53': CatalogMetadataEntry(angularSize: "13'", description: '머리털자리의 구상성단.'),
    'M54': CatalogMetadataEntry(angularSize: "12'", description: '궁수자리의 구상성단.'),
    'M55': CatalogMetadataEntry(angularSize: "19'", description: '궁수자리의 구상성단.'),
    'M56': CatalogMetadataEntry(angularSize: "8'", description: '백조자리의 구상성단.'),
    'M57': CatalogMetadataEntry(angularSize: "1.4' × 1.0'", description: '거문고자리의 행성상성운. 고리 성운.'),
    'M58': CatalogMetadataEntry(angularSize: "6' × 5'", description: '처녀자리의 나선은하.'),
    'M59': CatalogMetadataEntry(angularSize: "5' × 4'", description: '처녀자리의 타원은하.'),
    'M60': CatalogMetadataEntry(angularSize: "7' × 6'", description: '처녀자리의 타원은하.'),
    'M61': CatalogMetadataEntry(angularSize: "6' × 5'", description: '처녀자리의 나선은하.'),
    'M62': CatalogMetadataEntry(angularSize: "14'", description: '독수리자리의 구상성단.'),
    'M63': CatalogMetadataEntry(angularSize: "10' × 6'", description: '사냥개자리의 나선은하. Sunflower Galaxy.'),
    'M64': CatalogMetadataEntry(angularSize: "10' × 5'", description: '머리털자리의 나선은하. Black Eye Galaxy.'),
    'M65': CatalogMetadataEntry(angularSize: "10' × 3'", description: '사자자리의 나선은하. Leo Triplet.'),
    'M66': CatalogMetadataEntry(angularSize: "9' × 4'", description: '사자자리의 나선은하. Leo Triplet.'),
    'M67': CatalogMetadataEntry(angularSize: "30'", description: '게자리의 산개성단.'),
    'M68': CatalogMetadataEntry(angularSize: "12'", description: '바다뱀자리의 구상성단.'),
    'M69': CatalogMetadataEntry(angularSize: "12'", description: '궁수자리의 구상성단.'),
    'M70': CatalogMetadataEntry(angularSize: "8'", description: '궁수자리의 구상성단.'),
    'M71': CatalogMetadataEntry(angularSize: "7'", description: '화살자리의 구상성단.'),
    'M72': CatalogMetadataEntry(angularSize: "6'", description: '물뱀자리의 구상성단.'),
    'M73': CatalogMetadataEntry(angularSize: "2.8'", description: '물뱀자리의 산개성단.'),
    'M74': CatalogMetadataEntry(angularSize: "11' × 9'", description: '물고기자리의 나선은하.'),
    'M75': CatalogMetadataEntry(angularSize: "6'", description: '궁수자리의 구상성단.'),
    'M76': CatalogMetadataEntry(angularSize: "2.7' × 1.8'", description: '페르세우스자리의 행성상성운.'),
    'M77': CatalogMetadataEntry(angularSize: "7' × 6'", description: '고래자리의 나선은하.'),
    'M78': CatalogMetadataEntry(angularSize: "8' × 6'", description: '오리온자리의 반사성운.'),
    'M79': CatalogMetadataEntry(angularSize: "9'", description: '토끼자리의 구상성단.'),
    'M80': CatalogMetadataEntry(angularSize: "10'", description: '전갈자리의 구상성단.'),
    'M81': CatalogMetadataEntry(angularSize: "27' × 14'", description: '큰곰자리의 나선은하. Bode Galaxy.'),
    'M82': CatalogMetadataEntry(angularSize: "11' × 4'", description: '큰곰자리의 불규칙은하. Cigar Galaxy.'),
    'M83': CatalogMetadataEntry(angularSize: "13' × 11'", description: '물뱀자리의 나선은하.'),
    'M84': CatalogMetadataEntry(angularSize: "6' × 5'", description: '처녀자리의 렌즈형은하.'),
    'M85': CatalogMetadataEntry(angularSize: "7' × 5'", description: '사냥개자리의 렌즈형은하.'),
    'M86': CatalogMetadataEntry(angularSize: "8' × 5'", description: '처녀자리의 렌즈형은하.'),
    'M87': CatalogMetadataEntry(angularSize: "8' × 6'", description: '처녀자리의 타원은하. M87 제트.'),
    'M88': CatalogMetadataEntry(angularSize: "7' × 4'", description: '사냥개자리의 나선은하.'),
    'M89': CatalogMetadataEntry(angularSize: "5'", description: '처녀자리의 타원은하.'),
    'M90': CatalogMetadataEntry(angularSize: "10' × 5'", description: '처녀자리의 나선은하.'),
    'M91': CatalogMetadataEntry(angularSize: "5' × 4'", description: '사냥개자리의 나선은하.'),
    'M92': CatalogMetadataEntry(angularSize: "14'", description: '헤라클레스자리의 구상성단.'),
    'M93': CatalogMetadataEntry(angularSize: "22'", description: '고물자리의 산개성단.'),
    'M94': CatalogMetadataEntry(angularSize: "11' × 9'", description: '사냥개자리의 나선은하.'),
    'M95': CatalogMetadataEntry(angularSize: "7' × 5'", description: '사자자리의 나선은하.'),
    'M96': CatalogMetadataEntry(angularSize: "7' × 5'", description: '사자자리의 나선은하.'),
    'M97': CatalogMetadataEntry(angularSize: "3.4' × 3.3'", description: '큰곰자리의 행성상성운. 올빼미 성운.'),
    'M98': CatalogMetadataEntry(angularSize: "10' × 3'", description: '머리털자리의 나선은하.'),
    'M99': CatalogMetadataEntry(angularSize: "7' × 6'", description: '머리털자리의 나선은하.'),
    'M100': CatalogMetadataEntry(angularSize: "7' × 6'", description: '머리털자리의 나선은하.'),
    'M101': CatalogMetadataEntry(angularSize: "28' × 26'", description: '큰곰자리의 나선은하. Pinwheel Galaxy.'),
    'M102': CatalogMetadataEntry(angularSize: "5' × 2'", description: '북쪽왕관자리의 렌즈형은하.'),
    'M103': CatalogMetadataEntry(angularSize: "6'", description: '카시오페ia자리의 산개성단.'),
    'M104': CatalogMetadataEntry(angularSize: "9' × 4'", description: '처녀자리의 나선은하. Sombrero Galaxy.'),
    'M105': CatalogMetadataEntry(angularSize: "5' × 4'", description: '사자자리의 타원은하.'),
    'M106': CatalogMetadataEntry(angularSize: "19' × 7'", description: '사냥개자리의 나선은하.'),
    'M107': CatalogMetadataEntry(angularSize: "13'", description: '뱀자리의 구상성단.'),
    'M108': CatalogMetadataEntry(angularSize: "8' × 2'", description: '큰곰자리의 나선은하.'),
    'M109': CatalogMetadataEntry(angularSize: "7' × 4'", description: '큰곰자리의 나선은하.'),
    'M110': CatalogMetadataEntry(angularSize: "22' × 11'", description: '안드로메다 은하의 위성은하.'),
    'NGC 7000': CatalogMetadataEntry(angularSize: "120' × 100'", description: '북두자리의 발광성운. 북아메리카 성운.'),
    'IC 1396': CatalogMetadataEntry(angularSize: "170' × 140'", description: '세페우스자리의 발광성운. 코끼리 트렁크 성운.'),
    'NGC 6888': CatalogMetadataEntry(angularSize: "18' × 12'", description: '백조자리의 발광성운. 초승달 성운.'),
    'NGC 6960': CatalogMetadataEntry(angularSize: "60' × 8'", description: '백조자리의 초신성잔해. Veil Nebula.'),
    'NGC 2237': CatalogMetadataEntry(angularSize: "80'", description: '오리온자리의 발광성운. 장미 성운.'),
  };
}
