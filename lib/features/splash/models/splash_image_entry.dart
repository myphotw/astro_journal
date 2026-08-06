/// Splash 브랜드 이미지 한 장의 메타데이터.
///
/// 원격 URL + 로컬 파일명으로 관리하며, [tags]로 계절·테마 확장이 가능하다.
class SplashImageEntry {
  const SplashImageEntry({
    required this.id,
    required this.title,
    required this.fileName,
    required this.remoteUrl,
    this.tags = const [],
    this.credit,
  });

  /// 안정적 식별자 (직전 이미지 회피·버전 관리용).
  final String id;

  /// UI/로그용 표시 이름.
  final String title;

  /// 앱 저장소에 저장되는 파일명.
  final String fileName;

  /// 최초 다운로드용 원격 URL (공개 라이선스 권장).
  final String remoteUrl;

  /// 확장용 태그. 예: `spring`, `summer`, `winter`, `featured`.
  final List<String> tags;

  final String? credit;

  bool hasTag(String tag) => tags.contains(tag);
}
