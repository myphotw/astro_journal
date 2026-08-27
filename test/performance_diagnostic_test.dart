import 'dart:io';

import 'package:astro_journal/data/datasources/catalog_local_datasource.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/services/performance_probe.dart';
import 'package:astro_journal/data/models/observation_context.dart';
import 'package:astro_journal/data/models/tonight_observation_session.dart';
import 'package:astro_journal/services/celestial_position_service.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:astro_journal/services/recommendation_engine.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:astro_journal/services/scheduler_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'real catalog recommendation diagnostic',
    () async {
      final database = await openDatabase(
        File('assets/database/catalog_seed.db').absolute.path,
        readOnly: true,
      );
      addTearDown(database.close);

      final catalogStopwatch = Stopwatch()..start();
      final catalog = await CatalogLocalDataSource(
        database: database,
      ).getAll(listOnly: true);
      catalogStopwatch.stop();
      // ignore: avoid_print
      print(
        'PERF_DIAGNOSTIC catalog=${catalog.length} '
        'catalog_ms=${catalogStopwatch.elapsedMilliseconds}',
      );

      final session = TonightObservationSession(
        start: DateTime(2026, 8, 27, 20),
        end: DateTime(2026, 8, 28, 5),
      );
      final context = ObservationContext(
        latitude: 37.5,
        longitude: 127,
        brightness: 19,
        bortle: 8,
        moonIllumination: 0.2,
        moonAltitude: -10,
        moonAzimuth: 180,
        cloudCover: 0,
        observationStart: session.start,
        observationEnd: session.end,
        currentTime: session.start,
      );
      final cases = <({String name, Set<CatalogType> enabled})>[
        (name: 'messier_only', enabled: {CatalogType.messier}),
        (
          name: 'messier_caldwell',
          enabled: {CatalogType.messier, CatalogType.caldwell},
        ),
        (name: 'ngc_only', enabled: {CatalogType.ngc}),
        (
          name: 'all_selectable',
          enabled: CatalogType.values
              .where(
                (catalog) =>
                    catalog != CatalogType.solar &&
                    catalog != CatalogType.milky,
              )
              .toSet(),
        ),
      ];

      for (final diagnosticCase in cases) {
        final engine = RecommendationEngine(
          CelestialPositionService(),
          const ExposurePolicy(),
          const ObjectImagingProfileProvider(),
          const SchedulerEngine(),
        );
        final settings = RecommendationSettings(
          enabledCatalogs: diagnosticCase.enabled,
          azimuthStart: 0,
          azimuthEnd: 359,
          minAltitude: 0,
          maxAltitude: 90,
        );
        final userFiltered = catalog
            .where((object) => diagnosticCase.enabled.contains(object.catalog))
            .length;
        final recommendationStopwatch = Stopwatch()..start();
        PerformanceProbe.reset();
        final result = await engine.build(
          catalog: catalog,
          settings: settings,
          context: context,
          session: session,
          referenceTime: session.start,
        );
        recommendationStopwatch.stop();
        final batchStats = PerformanceProbe.stats(
          'recommendation.main_isolate_batch',
        );
        final windowStats = PerformanceProbe.stats('recommendation.window');
        final schedulerStats = PerformanceProbe.stats('scheduler.build');

        // Diagnostic values are printed for an evidence-based report.
        // Assertions intentionally avoid machine-dependent timing thresholds.
        // ignore: avoid_print
        print(
          'PERF_FILTER case=${diagnosticCase.name} catalog=${catalog.length} '
          'user_filtered=$userFiltered window_targets=$userFiltered '
          'recommendation_ms=${recommendationStopwatch.elapsedMilliseconds} '
          'window_ms=${windowStats.totalElapsedMs} '
          'scheduler_ms=${schedulerStats.totalElapsedMs} '
          'candidates=${result.scoredTargets.length} '
          'results=${result.allRecommendations.length} '
          'schedule=${result.scheduleItems.length} '
          'batch_count=${batchStats.count} '
          'batch_max_ms=${batchStats.maxElapsedMs}',
        );
        expect(
          result.scheduleResult.targets.every(
            (target) => diagnosticCase.enabled.contains(target.object.catalog),
          ),
          isTrue,
        );
      }
      expect(catalog.length, greaterThan(10000));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
