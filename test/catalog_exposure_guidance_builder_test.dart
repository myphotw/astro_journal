import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/catalog_exposure_guidance.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/imaging_suitability_assessment.dart';
import 'package:astro_journal/services/catalog_exposure_guidance_builder.dart';
import 'package:astro_journal/services/imaging_profile_resolver.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogExposureGuidanceBuilder', () {
    const builder = CatalogExposureGuidanceBuilder();
    const provider = ObjectImagingProfileProvider();

    CatalogObject object({
      required String id,
      required String type,
      String? objectType,
      String magnitude = '5.0',
      String? angularSize,
    }) {
      return CatalogObject(
        id: id,
        number: 1,
        catalog: CatalogType.messier,
        name: id,
        type: type,
        objectType: objectType,
        constellation: 'Test',
        ra: '0h',
        dec: '+0°',
        magnitude: magnitude,
        angularSize: angularSize,
      );
    }

    test('recommended state shows current exposure only', () {
      final profile = provider.profileFor(
        object(id: 'm45', type: '산개성단', objectType: '산개성단', magnitude: '1.6'),
      );
      final guidance = builder.build(profile: profile, referenceBortle: 8);

      expect(guidance.feasibility, CatalogExposureFeasibility.recommended);
      expect(guidance.currentExposureLine, isNotNull);
      expect(guidance.reason, isNull);
      expect(guidance.idealEnvironmentLabel, isNull);
    });

    test('not recommended shows a single reason without duplicate summary', () {
      final profile = provider.profileFor(
        object(id: 'm31', type: '은하', magnitude: '3.4'),
      );
      final guidance = builder.build(profile: profile, referenceBortle: 8);

      expect(guidance.feasibility, CatalogExposureFeasibility.notRecommended);
      expect(guidance.currentExposureLine, isNull);
      expect(guidance.reason, isNotNull);
      expect(guidance.reason, isNot(contains('•')));
      expect(guidance.idealEnvironmentLabel, isNotNull);
      expect(guidance.idealExposureLine, isNotNull);
    });

    test('strongly not recommended shows one short reason', () {
      final profile = provider.profileFor(
        object(id: 'dark1', type: '암흑성운', objectType: '암흑성운', magnitude: '9.0'),
      );
      final guidance = builder.build(profile: profile, referenceBortle: 8);

      expect(
        guidance.feasibility,
        CatalogExposureFeasibility.stronglyNotRecommended,
      );
      expect(guidance.reason, '현재 환경에서는 촬영을 권장하지 않습니다.');
      expect(guidance.currentExposureLine, isNull);
    });

    test('NGC 6822 uses the shared low-quality and Filter OFF assessment', () {
      final profile = provider.profileFor(
        object(
          id: 'ngc6822',
          type: '은하',
          objectType: '은하',
          magnitude: '10.05',
          angularSize: "17.38' × 16.75'",
        ),
      );
      final guidance = builder.build(profile: profile, referenceBortle: 8);

      expect(guidance.imagingAssessment, isNotNull);
      expect(guidance.imagingAssessment!.quality, ExpectedResultQuality.trace);
      expect(guidance.imagingAssessment!.filterMode, FilterMode.off);
    });
  });

  group('cluster exposure at Bortle 8', () {
    const builder = CatalogExposureGuidanceBuilder();
    const provider = ObjectImagingProfileProvider();
    const resolver = ImagingProfileResolver();

    CatalogObject cluster({
      required String id,
      required String objectType,
      required String magnitude,
    }) {
      return CatalogObject(
        id: id,
        number: 1,
        catalog: CatalogType.messier,
        name: id,
        type: objectType,
        objectType: objectType,
        constellation: 'Test',
        ra: '0h',
        dec: '+0°',
        magnitude: magnitude,
      );
    }

    test('open and globular clusters are shorter than before at Bortle 8', () {
      final m45 = builder.build(
        profile: provider.profileFor(
          cluster(id: 'm45', objectType: '산개성단', magnitude: '1.6'),
        ),
        referenceBortle: 8,
      );
      final m2 = builder.build(
        profile: provider.profileFor(
          cluster(id: 'm2', objectType: '구상성단', magnitude: '6.5'),
        ),
        referenceBortle: 8,
      );

      expect(m45.currentMinimumMinutes, lessThanOrEqualTo(30));
      expect(m2.currentMinimumMinutes, lessThanOrEqualTo(45));
      expect(m2.currentRecommendedMinutes, lessThanOrEqualTo(90));
    });

    test('M45 is brighter than M11 within open clusters', () {
      final m45Profile = resolver.resolve(
        cluster(id: 'm45', objectType: '산개성단', magnitude: '1.6'),
        ObjectType.openCluster,
      );
      final m11Profile = resolver.resolve(
        cluster(id: 'm11', objectType: '산개성단', magnitude: '6.3'),
        ObjectType.openCluster,
      );

      expect(
        m45Profile.surfaceBrightnessClass.tierIndex,
        lessThan(m11Profile.surfaceBrightnessClass.tierIndex),
      );
    });
  });
}
