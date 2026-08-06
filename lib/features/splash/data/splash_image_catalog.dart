import '../models/splash_image_entry.dart';

/// Splash 이미지 목록 (매니페스트).
///
/// 이미지를 추가·교체할 때는 이 목록과 [catalogVersion]만 갱신하면 된다.
/// 새 항목은 다음 실행 시 자동으로 다운로드된다.
///
/// 원격 소스는 Wikimedia Commons 공개 이미지(섬네일)를 사용한다.
class SplashImageCatalog {
  SplashImageCatalog._();

  /// 목록이 바뀌면 증가 → 신규 항목 다운로드 트리거.
  static const int catalogVersion = 1;

  static const List<SplashImageEntry> entries = [
    SplashImageEntry(
      id: 'm31_andromeda',
      title: '안드로메다은하 (M31)',
      fileName: 'm31_andromeda.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/9/98/Andromeda_Galaxy_%28with_h-alpha%29.jpg/1280px-Andromeda_Galaxy_%28with_h-alpha%29.jpg',
      tags: ['autumn', 'galaxy', 'featured'],
      credit: 'Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'm42_orion',
      title: '오리온 대성운 (M42)',
      fileName: 'm42_orion.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f3/Orion_Nebula_-_Hubble_2006_mosaic_18000.jpg/1280px-Orion_Nebula_-_Hubble_2006_mosaic_18000.jpg',
      tags: ['winter', 'nebula', 'featured'],
      credit: 'NASA/ESA Hubble / Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'm45_pleiades',
      title: '플레이아데스 (M45)',
      fileName: 'm45_pleiades.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Pleiades_large.jpg/1280px-Pleiades_large.jpg',
      tags: ['winter', 'cluster', 'featured'],
      credit: 'Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'north_america_nebula',
      title: '북아메리카 성운',
      fileName: 'north_america_nebula.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/6/6b/North_America_Nebula.jpg/1280px-North_America_Nebula.jpg',
      tags: ['summer', 'nebula'],
      credit: 'Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'rosette_nebula',
      title: '장미성운',
      fileName: 'rosette_nebula.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/3/32/Rosette_Nebula.jpg/1280px-Rosette_Nebula.jpg',
      tags: ['winter', 'nebula'],
      credit: 'Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'milky_way',
      title: '은하수',
      fileName: 'milky_way.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/ESO-VLT-Laser-phot-33a-07.jpg/1280px-ESO-VLT-Laser-phot-33a-07.jpg',
      tags: ['summer', 'milkyway', 'featured'],
      credit: 'ESO / Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'veil_nebula',
      title: '베일성운',
      fileName: 'veil_nebula.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Veil_Nebula_-_NGC6960.jpg/1280px-Veil_Nebula_-_NGC6960.jpg',
      tags: ['summer', 'nebula'],
      credit: 'Wikimedia Commons',
    ),
    SplashImageEntry(
      id: 'horsehead_nebula',
      title: '말머리성운',
      fileName: 'horsehead_nebula.jpg',
      remoteUrl:
          'https://upload.wikimedia.org/wikipedia/commons/thumb/6/68/Barnard_33.jpg/1280px-Barnard_33.jpg',
      tags: ['winter', 'nebula', 'featured'],
      credit: 'Wikimedia Commons',
    ),
  ];

  static SplashImageEntry? byId(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// 태그 필터 (향후 계절 테마용).
  static List<SplashImageEntry> byTag(String tag) {
    return entries.where((e) => e.hasTag(tag)).toList(growable: false);
  }
}
