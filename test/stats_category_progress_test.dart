import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/policies/catalog_deletion_policy.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/features/stats/view/widgets/catalog_category_progress_card.dart';
import 'package:astro_journal/services/stats_analytics_service.dart';
import 'package:astro_journal/services/stats_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = StatsAnalyticsService();

  group('category progress calculation', () {
    test('returns zero progress without canonical records', () {
      final result = service.buildCategoryProgress(
        records: const [],
        catalog: [
          _object('M1', CatalogType.messier, 1),
          _object('M2', CatalogType.messier, 2),
        ],
      );

      final messier = _of(result, CatalogType.messier);
      expect(messier.total, 2);
      expect(messier.captured, 0);
      expect(messier.progress, 0);
    });

    test('calculates partial and complete progress', () {
      final catalog = [
        _object('M1', CatalogType.messier, 1),
        _object('M2', CatalogType.messier, 2),
      ];
      final partial = service.buildCategoryProgress(
        records: [_record('r1', 'M1')],
        catalog: catalog,
      );
      final complete = service.buildCategoryProgress(
        records: [_record('r1', 'M1'), _record('r2', 'M2')],
        catalog: catalog,
      );

      expect(_of(partial, CatalogType.messier).captured, 1);
      expect(_of(partial, CatalogType.messier).progressPercent, 50);
      expect(_of(complete, CatalogType.messier).captured, 2);
      expect(_of(complete, CatalogType.messier).progressPercent, 100);
    });

    test('uses canonical primary identity for cross-catalog records', () {
      final result = service.buildCategoryProgress(
        records: [_record('remote', 'NGC224')],
        catalog: [
          _object('M31', CatalogType.messier, 31),
          _object(
            'NGC224',
            CatalogType.ngc,
            224,
            primaryCatalogId: 'M31',
            isPrimaryCatalog: false,
          ),
        ],
      );

      expect(_of(result, CatalogType.messier).captured, 1);
      expect(_of(result, CatalogType.ngc).captured, 1);
    });

    test('keeps custom targets and excludes deleted targets', () {
      final result = service.buildCategoryProgress(
        records: [
          _record('custom-record', '5bc9bdc0-4ff8-4d10-9c39-c19c1d5f00aa'),
          _record('deleted-record', 'deleted-custom'),
        ],
        catalog: [
          _object(
            '5bc9bdc0-4ff8-4d10-9c39-c19c1d5f00aa',
            CatalogType.star,
            1,
            tags: const [CatalogDeletionPolicy.userCreatedTag],
          ),
          _object(
            'deleted-custom',
            CatalogType.star,
            2,
            tags: const [
              CatalogDeletionPolicy.userCreatedTag,
              CatalogDeletionPolicy.deletedTag,
            ],
          ),
        ],
      );

      final star = _of(result, CatalogType.star);
      expect(star.total, 1);
      expect(star.captured, 1);
    });

    test('record-only comet uses the existing Solar progress policy', () {
      final result = service.buildCategoryProgress(
        records: [_record('halley-record', 'solar_11')],
        catalog: [
          _object('solar_8', CatalogType.solar, 8),
          _object(
            'solar_11',
            CatalogType.solar,
            11,
            tags: const ['record_only', 'dynamic_ephemeris'],
          ),
        ],
      );

      final solar = _of(result, CatalogType.solar);
      expect(solar.total, 2);
      expect(solar.captured, 1);
      expect(solar.progressPercent, 50);
    });
  });

  testWidgets('renders count, percent and responsive progress bars', (
    tester,
  ) async {
    final progress = service.buildCategoryProgress(
      records: [_record('r1', 'M1')],
      catalog: [
        _object('M1', CatalogType.messier, 1),
        _object('M2', CatalogType.messier, 2),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CatalogCategoryProgressCard(progress: progress),
          ),
        ),
      ),
    );

    expect(find.text('카테고리별 진행률'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(
      find.byType(LinearProgressIndicator),
      findsNWidgets(progress.length),
    );
    expect(
      find.byKey(const Key('stats-category-progress-1column')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

CatalogObject _object(
  String id,
  CatalogType type,
  int number, {
  String? primaryCatalogId,
  bool isPrimaryCatalog = true,
  List<String> tags = const [],
}) => CatalogObject(
  id: id,
  number: number,
  catalog: type,
  name: id,
  type: 'Other',
  constellation: '-',
  ra: '-',
  dec: '-',
  magnitude: '-',
  primaryCatalogId: primaryCatalogId,
  isPrimaryCatalog: isPrimaryCatalog,
  tags: tags,
);

ShootingRecord _record(String id, String objectId) => ShootingRecord(
  id: id,
  celestialObjectId: objectId,
  capturedAt: DateTime(2026, 8, 20),
  createdAt: DateTime(2026, 8, 20),
);

CatalogCategoryProgress _of(
  List<CatalogCategoryProgress> progress,
  CatalogType type,
) => progress.firstWhere((item) => item.type == type);
