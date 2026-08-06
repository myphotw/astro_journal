import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/services/stats_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = StatsAnalyticsService();
  final now = DateTime(2026, 7, 2);

  CatalogObject catalog({
    required String id,
    required String name,
    int number = 1,
    CatalogType catalogType = CatalogType.messier,
    String? objectType,
  }) {
    return CatalogObject(
      id: id,
      number: number,
      catalog: catalogType,
      name: name,
      type: objectType ?? '발광성운',
      objectType: objectType,
      constellation: 'Ori',
      ra: '05h 35m',
      dec: '-05° 23\'',
      magnitude: '4.0',
      commonName: '$name 별칭',
    );
  }

  ShootingRecord record({
    required String id,
    required String objectId,
    required DateTime capturedAt,
    String exposure = '',
  }) {
    return ShootingRecord(
      id: id,
      celestialObjectId: objectId,
      capturedAt: capturedAt,
      createdAt: capturedAt,
      exif: exposure.isEmpty
          ? null
          : ExifInfo(
              filename: '$id.jpg',
              size: '1MB',
              date: capturedAt.toIso8601String(),
              equipment: 'Seestar',
              focal: '300mm',
              fstop: 'f/5',
              exposure: exposure,
              iso: 'ISO 100',
              resolution: '1920x1080',
            ),
    );
  }

  group('StatsAnalyticsService', () {
    test('builds KPI and monthly stats for current year', () {
      final catalogById = {
        'm42': catalog(id: 'm42', name: 'M42', number: 42),
        'm31': catalog(
          id: 'm31',
          name: 'M31',
          number: 31,
          objectType: ObjectType.galaxy.label,
        ),
      };

      final records = [
        record(
          id: 'r1',
          objectId: 'm42',
          capturedAt: DateTime(2026, 3, 10),
          exposure: '4분20초',
        ),
        record(
          id: 'r2',
          objectId: 'm42',
          capturedAt: DateTime(2026, 7, 1),
          exposure: '20초',
        ),
        record(
          id: 'r3',
          objectId: 'm31',
          capturedAt: DateTime(2026, 7, 2),
        ),
        record(
          id: 'r4',
          objectId: 'm31',
          capturedAt: DateTime(2025, 12, 31),
          exposure: '1분',
        ),
      ];

      final dashboard = service.buildDashboard(
        records: records,
        catalogById: catalogById,
        now: now,
      );

      expect(dashboard.kpi.totalShootCount, 4);
      expect(dashboard.kpi.totalTargetCount, 2);
      expect(dashboard.kpi.totalIntegrationSeconds, 340);
      expect(dashboard.kpi.averageIntegrationSeconds, 85);

      expect(dashboard.monthlyStats[2].shootCount, 1);
      expect(dashboard.monthlyStats[2].integrationSeconds, 260);
      expect(dashboard.monthlyStats[6].shootCount, 2);
      expect(dashboard.monthlyStats[6].integrationSeconds, 20);

      expect(dashboard.currentMonth.shootCount, 2);
      expect(dashboard.currentMonth.integrationSeconds, 20);
    });

    test('orders top targets by integration seconds', () {
      final catalogById = {
        'm42': catalog(id: 'm42', name: 'M42', number: 42),
        'm31': catalog(id: 'm31', name: 'M31', number: 31),
      };

      final records = [
        record(
          id: 'r1',
          objectId: 'm31',
          capturedAt: DateTime(2026, 1, 1),
          exposure: '10분',
        ),
        record(
          id: 'r2',
          objectId: 'm42',
          capturedAt: DateTime(2026, 2, 1),
          exposure: '30분',
        ),
      ];

      final dashboard = service.buildDashboard(
        records: records,
        catalogById: catalogById,
        now: now,
      );

      expect(dashboard.topTargets.length, 2);
      expect(dashboard.topTargets.first.displayName, 'M42');
      expect(dashboard.topTargets.first.integrationSeconds, 1800);
      expect(dashboard.topTargets.first.shootCount, 1);
    });

    test('builds year achievement summary', () {
      final catalogById = {
        'm42': catalog(id: 'm42', name: 'M42', number: 42),
        'm31': catalog(id: 'm31', name: 'M31', number: 31),
      };

      final records = [
        record(
          id: 'old',
          objectId: 'm42',
          capturedAt: DateTime(2025, 5, 1),
          exposure: '5분',
        ),
        record(
          id: 'new1',
          objectId: 'm31',
          capturedAt: DateTime(2026, 1, 1),
          exposure: '10분',
        ),
        record(
          id: 'new2',
          objectId: 'm31',
          capturedAt: DateTime(2026, 2, 1),
          exposure: '5분',
        ),
        record(
          id: 'new3',
          objectId: 'm42',
          capturedAt: DateTime(2026, 3, 1),
          exposure: '20분',
        ),
      ];

      final dashboard = service.buildDashboard(
        records: records,
        catalogById: catalogById,
        now: now,
      );

      expect(dashboard.yearAchievement.year, 2026);
      expect(dashboard.yearAchievement.newTargetCount, 1);
      expect(dashboard.yearAchievement.totalIntegrationSeconds, 2100);
      expect(dashboard.yearAchievement.mostShotTarget, contains('M31'));
      expect(
        dashboard.yearAchievement.longestIntegrationTarget,
        contains('M42'),
      );
    });
  });

  group('buildMonthlyDetail', () {
    test('returns monthly breakdown with new targets and top performers', () {
      final catalogById = {
        'm42': catalog(id: 'm42', name: 'M42', number: 42),
        'm31': catalog(id: 'm31', name: 'M31', number: 31),
        'ngc7000': catalog(
          id: 'ngc7000',
          name: 'NGC7000',
          number: 7000,
          catalogType: CatalogType.ngc,
          objectType: ObjectType.emissionNebula.label,
        ),
      };

      final records = [
        record(
          id: 'old',
          objectId: 'm42',
          capturedAt: DateTime(2026, 5, 1),
          exposure: '5분',
        ),
        record(
          id: 'june1',
          objectId: 'm31',
          capturedAt: DateTime(2026, 6, 10),
          exposure: '10분',
        ),
        record(
          id: 'june2',
          objectId: 'm31',
          capturedAt: DateTime(2026, 6, 20),
          exposure: '5분',
        ),
        record(
          id: 'june3',
          objectId: 'm42',
          capturedAt: DateTime(2026, 6, 25),
          exposure: '20분',
        ),
        record(
          id: 'june4',
          objectId: 'ngc7000',
          capturedAt: DateTime(2026, 6, 28),
          exposure: '15분',
        ),
      ];

      final detail = service.buildMonthlyDetail(
        records: records,
        catalogById: catalogById,
        year: 2026,
        month: 6,
      );

      expect(detail.title, '2026년 6월');
      expect(detail.shootCount, 4);
      expect(detail.totalIntegrationSeconds, 3000);
      expect(detail.newTargetCount, 2);
      expect(detail.averageIntegrationSeconds, 750);
      expect(detail.mostShotTarget, contains('M31'));
      expect(detail.longestIntegrationTarget, contains('M42'));
      expect(detail.topThreeTargets.length, 3);
      expect(detail.topThreeTargets[0], contains('M42'));
      expect(detail.topThreeTargets[1], contains('M31'));
      expect(detail.topThreeTargets[2], contains('NGC 7000'));
    });
  });

  group('buildYearAchievement', () {
    test('builds achievement for selected year', () {
      final catalogById = {
        'm42': catalog(id: 'm42', name: 'M42', number: 42),
        'm31': catalog(id: 'm31', name: 'M31', number: 31),
      };

      final records = [
        record(
          id: 'y25',
          objectId: 'm42',
          capturedAt: DateTime(2025, 8, 1),
          exposure: '1시간',
        ),
        record(
          id: 'y26',
          objectId: 'm31',
          capturedAt: DateTime(2026, 1, 1),
          exposure: '30분',
        ),
      ];

      final year2025 = service.buildYearAchievement(
        records: records,
        catalogById: catalogById,
        year: 2025,
      );
      final year2026 = service.buildYearAchievement(
        records: records,
        catalogById: catalogById,
        year: 2026,
      );

      expect(year2025.totalIntegrationSeconds, 3600);
      expect(year2025.newTargetCount, 1);
      expect(year2026.totalIntegrationSeconds, 1800);
      expect(year2026.newTargetCount, 1);
    });
  });

  group('listAchievementYears', () {
    test('returns record years plus current year sorted descending', () {
      final records = [
        record(
          id: 'r1',
          objectId: 'm42',
          capturedAt: DateTime(2025, 1, 1),
        ),
        record(
          id: 'r2',
          objectId: 'm31',
          capturedAt: DateTime(2026, 1, 1),
        ),
      ];

      expect(
        service.listAchievementYears(records, now: DateTime(2026, 7, 2)),
        [2026, 2025],
      );
    });
  });
}
