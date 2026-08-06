import 'package:flutter/material.dart';

/// Dashboard KPI 요약.
class StatsKpiSummary {
  const StatsKpiSummary({
    required this.totalShootCount,
    required this.totalTargetCount,
    required this.totalIntegrationSeconds,
    required this.averageIntegrationSeconds,
  });

  final int totalShootCount;
  final int totalTargetCount;
  final double totalIntegrationSeconds;
  final double averageIntegrationSeconds;
}

/// 올해 월별 통계 포인트.
class MonthlyStatsPoint {
  const MonthlyStatsPoint({
    required this.month,
    required this.label,
    required this.shootCount,
    required this.integrationSeconds,
  });

  final int month;
  final String label;
  final int shootCount;
  final double integrationSeconds;
}

/// 이번 달 하이라이트.
class MonthlyHighlight {
  const MonthlyHighlight({
    required this.shootCount,
    required this.integrationSeconds,
    required this.averageIntegrationSeconds,
  });

  final int shootCount;
  final double integrationSeconds;
  final double averageIntegrationSeconds;
}

/// 월별 상세 통계 (Bottom Sheet·향후 확장용).
class MonthlyDetailStats {
  const MonthlyDetailStats({
    required this.year,
    required this.month,
    required this.title,
    required this.totalIntegrationSeconds,
    required this.shootCount,
    required this.newTargetCount,
    required this.averageIntegrationSeconds,
    required this.mostShotTarget,
    required this.longestIntegrationTarget,
    required this.topThreeTargets,
  });

  final int year;
  final int month;
  final String title;
  final double totalIntegrationSeconds;
  final int shootCount;
  final int newTargetCount;
  final double averageIntegrationSeconds;
  final String? mostShotTarget;
  final String? longestIntegrationTarget;

  /// 해당 월 적산시간 기준 TOP3 대상 표시명.
  final List<String> topThreeTargets;
}

/// TOP 촬영 대상 통계.
class TopTargetStat {
  const TopTargetStat({
    required this.objectId,
    required this.displayName,
    required this.alias,
    required this.integrationSeconds,
    required this.shootCount,
  });

  final String objectId;
  final String displayName;
  final String alias;
  final double integrationSeconds;
  final int shootCount;
}

/// 도넛 차트용 천체 분류 비율.
class ObjectTypeBreakdown {
  const ObjectTypeBreakdown({
    required this.category,
    required this.count,
    required this.ratio,
    required this.color,
  });

  final String category;
  final int count;
  final double ratio;
  final Color color;
}

/// 올해의 성과.
class YearAchievementSummary {
  const YearAchievementSummary({
    required this.year,
    required this.newTargetCount,
    required this.totalIntegrationSeconds,
    required this.mostShotTarget,
    required this.longestIntegrationTarget,
  });

  final int year;
  final int newTargetCount;
  final double totalIntegrationSeconds;
  final String? mostShotTarget;
  final String? longestIntegrationTarget;
}

/// 통계 Dashboard 전체 데이터.
class StatsDashboardData {
  const StatsDashboardData({
    required this.kpi,
    required this.monthlyStats,
    required this.currentMonth,
    required this.topTargets,
    required this.typeBreakdown,
    required this.yearAchievement,
    required this.referenceYear,
  });

  final StatsKpiSummary kpi;
  final List<MonthlyStatsPoint> monthlyStats;
  final MonthlyHighlight currentMonth;
  final List<TopTargetStat> topTargets;
  final List<ObjectTypeBreakdown> typeBreakdown;
  final YearAchievementSummary yearAchievement;

  /// 월별 차트·이번 달 요약에 사용하는 기준 연도.
  final int referenceYear;
}
