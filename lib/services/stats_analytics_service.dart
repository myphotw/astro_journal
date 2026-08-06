import 'package:flutter/material.dart';

import '../core/constants/object_type.dart';
import '../data/models/catalog_object.dart';
import '../data/models/shooting_record.dart';
import 'exposure_duration_parser.dart';
import 'stats_models.dart';

/// 촬영 기록 기반 통계 Dashboard 집계 (SSOT).
class StatsAnalyticsService {
  StatsAnalyticsService({
    ExposureDurationParser? exposureParser,
  }) : _exposureParser = exposureParser ?? const ExposureDurationParser();

  final ExposureDurationParser _exposureParser;

  static const _typePalette = <Color>[
    Color(0xFF7986CB),
    Color(0xFF4DD0E1),
    Color(0xFF9575CD),
    Color(0xFF78909C),
    Color(0xFF64B5F6),
    Color(0xFF81C784),
    Color(0xFFFFB74D),
    Color(0xFF90A4AE),
  ];

  StatsDashboardData buildDashboard({
    required List<ShootingRecord> records,
    required Map<String, CatalogObject> catalogById,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final year = reference.year;
    final currentMonth = reference.month;

    final integrationByRecord = <String, double>{
      for (final record in records)
        record.id: _integrationSecondsFor(record),
    };

    final totalIntegration = integrationByRecord.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final shootCount = records.length;
    final targetCount =
        records.map((record) => record.celestialObjectId).toSet().length;

    final kpi = StatsKpiSummary(
      totalShootCount: shootCount,
      totalTargetCount: targetCount,
      totalIntegrationSeconds: totalIntegration,
      averageIntegrationSeconds:
          shootCount == 0 ? 0 : totalIntegration / shootCount,
    );

    final monthlyStats = List.generate(12, (index) {
      final month = index + 1;
      final monthRecords = records.where(
        (record) =>
            record.capturedAt.year == year &&
            record.capturedAt.month == month,
      );
      final integration = monthRecords.fold<double>(
        0,
        (sum, record) => sum + (integrationByRecord[record.id] ?? 0),
      );
      return MonthlyStatsPoint(
        month: month,
        label: '$month월',
        shootCount: monthRecords.length,
        integrationSeconds: integration,
      );
    });

    final thisMonthRecords = records.where(
      (record) =>
          record.capturedAt.year == year &&
          record.capturedAt.month == currentMonth,
    );
    final thisMonthIntegration = thisMonthRecords.fold<double>(
      0,
      (sum, record) => sum + (integrationByRecord[record.id] ?? 0),
    );
    final thisMonthCount = thisMonthRecords.length;

    final currentMonthHighlight = MonthlyHighlight(
      shootCount: thisMonthCount,
      integrationSeconds: thisMonthIntegration,
      averageIntegrationSeconds:
          thisMonthCount == 0 ? 0 : thisMonthIntegration / thisMonthCount,
    );

    final topTargets = _buildTopTargets(
      records: records,
      integrationByRecord: integrationByRecord,
      catalogById: catalogById,
    );

    final typeBreakdown = _buildTypeBreakdown(
      records: records,
      catalogById: catalogById,
    );

    final yearAchievement = _buildYearAchievement(
      records: records,
      integrationByRecord: integrationByRecord,
      catalogById: catalogById,
      year: year,
    );

    return StatsDashboardData(
      kpi: kpi,
      monthlyStats: monthlyStats,
      currentMonth: currentMonthHighlight,
      topTargets: topTargets,
      typeBreakdown: typeBreakdown,
      yearAchievement: yearAchievement,
      referenceYear: year,
    );
  }

  /// 성과 카드에서 선택 가능한 연도 목록 (내림차순).
  List<int> listAchievementYears(
    List<ShootingRecord> records, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final years = records.map((record) => record.capturedAt.year).toSet();
    years.add(reference.year);
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  /// 특정 연도의 성과 요약.
  YearAchievementSummary buildYearAchievement({
    required List<ShootingRecord> records,
    required Map<String, CatalogObject> catalogById,
    required int year,
  }) {
    final integrationByRecord = <String, double>{
      for (final record in records)
        record.id: _integrationSecondsFor(record),
    };
    return _buildYearAchievement(
      records: records,
      integrationByRecord: integrationByRecord,
      catalogById: catalogById,
      year: year,
    );
  }

  /// 특정 연·월의 상세 통계 (Bottom Sheet 등).
  MonthlyDetailStats buildMonthlyDetail({
    required List<ShootingRecord> records,
    required Map<String, CatalogObject> catalogById,
    required int year,
    required int month,
  }) {
    final integrationByRecord = <String, double>{
      for (final record in records)
        record.id: _integrationSecondsFor(record),
    };

    final monthRecords = records
        .where(
          (record) =>
              record.capturedAt.year == year &&
              record.capturedAt.month == month,
        )
        .toList();

    final totalIntegration = monthRecords.fold<double>(
      0,
      (sum, record) => sum + (integrationByRecord[record.id] ?? 0),
    );
    final shootCount = monthRecords.length;

    final firstCaptureByTarget = <String, DateTime>{};
    for (final record in records) {
      final id = record.celestialObjectId;
      final existing = firstCaptureByTarget[id];
      if (existing == null || record.capturedAt.isBefore(existing)) {
        firstCaptureByTarget[id] = record.capturedAt;
      }
    }

    final newTargetCount = monthRecords
        .map((record) => record.celestialObjectId)
        .toSet()
        .where((id) {
          final first = firstCaptureByTarget[id];
          return first != null &&
              first.year == year &&
              first.month == month;
        })
        .length;

    final countByTarget = <String, int>{};
    final integrationByTarget = <String, double>{};
    for (final record in monthRecords) {
      final id = record.celestialObjectId;
      countByTarget[id] = (countByTarget[id] ?? 0) + 1;
      integrationByTarget[id] =
          (integrationByTarget[id] ?? 0) + (integrationByRecord[record.id] ?? 0);
    }

    String? mostShot;
    if (countByTarget.isNotEmpty) {
      final topId = countByTarget.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      mostShot = _targetLabel(topId, catalogById);
    }

    String? longestIntegration;
    if (integrationByTarget.isNotEmpty) {
      final topId = integrationByTarget.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      longestIntegration = _targetLabel(topId, catalogById);
    }

    final topThreeTargets = integrationByTarget.entries.toList()
      ..sort((a, b) {
        final byIntegration = b.value.compareTo(a.value);
        if (byIntegration != 0) return byIntegration;
        return (countByTarget[b.key] ?? 0).compareTo(countByTarget[a.key] ?? 0);
      });

    final topThreeNames = topThreeTargets
        .take(3)
        .map((entry) => _targetLabel(entry.key, catalogById))
        .toList();

    return MonthlyDetailStats(
      year: year,
      month: month,
      title: '$year년 $month월',
      totalIntegrationSeconds: totalIntegration,
      shootCount: shootCount,
      newTargetCount: newTargetCount,
      averageIntegrationSeconds:
          shootCount == 0 ? 0 : totalIntegration / shootCount,
      mostShotTarget: mostShot,
      longestIntegrationTarget: longestIntegration,
      topThreeTargets: topThreeNames,
    );
  }

  double _integrationSecondsFor(ShootingRecord record) {
    final exposure = record.exif?.exposure;
    if (exposure != null && exposure.trim().isNotEmpty) {
      return _exposureParser.parse(exposure);
    }
    return 0;
  }

  List<TopTargetStat> _buildTopTargets({
    required List<ShootingRecord> records,
    required Map<String, double> integrationByRecord,
    required Map<String, CatalogObject> catalogById,
  }) {
    final integrationByTarget = <String, double>{};
    final countByTarget = <String, int>{};

    for (final record in records) {
      final id = record.celestialObjectId;
      integrationByTarget[id] =
          (integrationByTarget[id] ?? 0) + (integrationByRecord[record.id] ?? 0);
      countByTarget[id] = (countByTarget[id] ?? 0) + 1;
    }

    final sortedIds = integrationByTarget.keys.toList()
      ..sort(
        (a, b) => integrationByTarget[b]!.compareTo(integrationByTarget[a]!),
      );

    return sortedIds.take(10).map((id) {
      final object = catalogById[id];
      return TopTargetStat(
        objectId: id,
        displayName: object?.displayName ?? id,
        alias: object?.displayCommonName ?? '-',
        integrationSeconds: integrationByTarget[id] ?? 0,
        shootCount: countByTarget[id] ?? 0,
      );
    }).toList();
  }

  List<ObjectTypeBreakdown> _buildTypeBreakdown({
    required List<ShootingRecord> records,
    required Map<String, CatalogObject> catalogById,
  }) {
    final counts = <String, int>{};
    for (final record in records) {
      final object = catalogById[record.celestialObjectId];
      final category = _dashboardCategory(object);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    if (counts.isEmpty) return const [];

    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    final sortedEntries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return List.generate(sortedEntries.length, (index) {
      final entry = sortedEntries[index];
      return ObjectTypeBreakdown(
        category: entry.key,
        count: entry.value,
        ratio: entry.value / total,
        color: _typePalette[index % _typePalette.length],
      );
    });
  }

  YearAchievementSummary _buildYearAchievement({
    required List<ShootingRecord> records,
    required Map<String, double> integrationByRecord,
    required Map<String, CatalogObject> catalogById,
    required int year,
  }) {
    final yearRecords =
        records.where((record) => record.capturedAt.year == year).toList();

    final firstCaptureByTarget = <String, DateTime>{};
    for (final record in records) {
      final id = record.celestialObjectId;
      final existing = firstCaptureByTarget[id];
      if (existing == null || record.capturedAt.isBefore(existing)) {
        firstCaptureByTarget[id] = record.capturedAt;
      }
    }

    final newTargetCount = firstCaptureByTarget.entries
        .where((entry) => entry.value.year == year)
        .length;

    final yearIntegration = yearRecords.fold<double>(
      0,
      (sum, record) => sum + (integrationByRecord[record.id] ?? 0),
    );

    final countByTarget = <String, int>{};
    final integrationByTarget = <String, double>{};
    for (final record in yearRecords) {
      final id = record.celestialObjectId;
      countByTarget[id] = (countByTarget[id] ?? 0) + 1;
      integrationByTarget[id] =
          (integrationByTarget[id] ?? 0) + (integrationByRecord[record.id] ?? 0);
    }

    String? mostShot;
    if (countByTarget.isNotEmpty) {
      final topId = countByTarget.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      mostShot = _targetLabel(topId, catalogById);
    }

    String? longestIntegration;
    if (integrationByTarget.isNotEmpty) {
      final topId = integrationByTarget.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      longestIntegration = _targetLabel(topId, catalogById);
    }

    return YearAchievementSummary(
      year: year,
      newTargetCount: newTargetCount,
      totalIntegrationSeconds: yearIntegration,
      mostShotTarget: mostShot,
      longestIntegrationTarget: longestIntegration,
    );
  }

  String _targetLabel(String id, Map<String, CatalogObject> catalogById) {
    final object = catalogById[id];
    if (object == null) return id;
    final alias = object.displayCommonName;
    if (alias.isNotEmpty && alias != object.displayName) {
      return '${object.displayName} ($alias)';
    }
    return object.displayName;
  }

  String _dashboardCategory(CatalogObject? object) {
    if (object == null) return '기타';

    switch (object.resolvedObjectType) {
      case ObjectType.emissionNebula:
      case ObjectType.complexNebula:
      case ObjectType.nebulaWithCluster:
      case ObjectType.supernovaRemnant:
        return '발광성운';
      case ObjectType.reflectionNebula:
        return '반사성운';
      case ObjectType.darkNebula:
        return '암흑성운';
      case ObjectType.galaxy:
      case ObjectType.galaxyGroup:
        return '은하';
      case ObjectType.openCluster:
        return '산개성단';
      case ObjectType.globularCluster:
        return '구상성단';
      case ObjectType.planetaryNebula:
        return '행성상성운';
      default:
        return '기타';
    }
  }
}
