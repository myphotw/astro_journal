/// 천체 관측용 계절 (북반구 기준, 월 단위).
enum AstroSeason {
  spring,
  summer,
  autumn,
  winter;

  String get label {
    switch (this) {
      case AstroSeason.spring:
        return '봄';
      case AstroSeason.summer:
        return '여름';
      case AstroSeason.autumn:
        return '가을';
      case AstroSeason.winter:
        return '겨울';
    }
  }

  String get subtitle {
    switch (this) {
      case AstroSeason.spring:
        return '3~5월';
      case AstroSeason.summer:
        return '6~8월';
      case AstroSeason.autumn:
        return '9~11월';
      case AstroSeason.winter:
        return '12~2월';
    }
  }

  /// 해당 계절에 포함되는 달 (1~12).
  List<int> get months {
    switch (this) {
      case AstroSeason.spring:
        return const [3, 4, 5];
      case AstroSeason.summer:
        return const [6, 7, 8];
      case AstroSeason.autumn:
        return const [9, 10, 11];
      case AstroSeason.winter:
        return const [12, 1, 2];
    }
  }

  static AstroSeason fromMonth(int month) {
    if (month >= 3 && month <= 5) return AstroSeason.spring;
    if (month >= 6 && month <= 8) return AstroSeason.summer;
    if (month >= 9 && month <= 11) return AstroSeason.autumn;
    return AstroSeason.winter;
  }
}
