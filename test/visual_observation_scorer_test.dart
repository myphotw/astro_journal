import 'package:astro_journal/core/constants/catalog_type.dart';

import 'package:astro_journal/core/constants/equipment_kind.dart';

import 'package:astro_journal/core/constants/equipment_purpose.dart';

import 'package:astro_journal/core/constants/object_type.dart';

import 'package:astro_journal/data/models/catalog_object.dart';

import 'package:astro_journal/data/models/equipment.dart';

import 'package:astro_journal/data/models/eyepiece.dart';

import 'package:astro_journal/data/models/object_imaging_profile.dart';

import 'package:astro_journal/core/constants/angular_size_class.dart';

import 'package:astro_journal/core/constants/imaging_difficulty.dart';

import 'package:astro_journal/core/constants/surface_brightness_class.dart';

import 'package:astro_journal/data/models/representative_framing_size.dart';

import 'package:astro_journal/services/equipment/visual_observation_scorer.dart';
import 'package:astro_journal/services/equipment/visual_target_context.dart';

import 'package:flutter_test/flutter_test.dart';



void main() {

  const scorer = VisualObservationScorer();



  Equipment bcto90() {

    return Equipment(

      id: 'bcto',

      name: 'BCTO90',

      kind: EquipmentKind.reflector,

      purpose: EquipmentPurpose.visual,

      apertureMm: 90,

      focalLengthMm: 500,

      eyepieces: const [

        Eyepiece(

          id: 'ep25',

          equipmentId: 'bcto',

          name: '25mm',

          focalLengthMm: 25,

          afovDegrees: 50,

        ),

        Eyepiece(

          id: 'ep6',

          equipmentId: 'bcto',

          name: '6mm',

          focalLengthMm: 6,

          afovDegrees: 52,

        ),

      ],

    );

  }



  CatalogObject catalogObject({

    required String id,

    String type = '구상성단',

    String? commonName,

    String magnitude = '5.8',

  }) {

    return CatalogObject(

      id: id,

      number: 13,

      catalog: CatalogType.messier,

      name: id.toUpperCase(),

      type: type,

      constellation: 'Test',

      ra: '16h41m',

      dec: "+36°28'",

      magnitude: magnitude,

      commonName: commonName,

    );

  }



  VisualTargetContext contextFor({

    required CatalogObject object,

    ObjectType objectType = ObjectType.globularCluster,

    SurfaceBrightnessClass brightness = SurfaceBrightnessClass.normal,

    AngularSizeClass angularSize = AngularSizeClass.small,

    double widthArcmin = 10.2,
    double heightArcmin = 10.2,
  }) {
    return VisualTargetContext.from(
      object: object,
      profile: ObjectImagingProfile(
        objectType: objectType,
        imagingDifficulty: ImagingDifficulty.normal,
        surfaceBrightnessClass: brightness,
        angularSizeClass: angularSize,
        baseExposureMinutes: 30,
        minimumRecommendedBortle: 7,
        recommendedBortle: 4,
        supportsNarrowband: false,
        recommendedFilters: const ['L'],
      ),
      framingSize: RepresentativeFramingSize(
        widthArcmin: widthArcmin,
        heightArcmin: heightArcmin,
      ),
    );

  }



  group('VisualObservationScorer', () {

    test('recommends M13 with eyepiece for 90mm scope', () {

      final result = scorer.bestRecommendation(

        context: contextFor(object: catalogObject(id: 'm13')),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isTrue);

      expect(result.eyepiece, isNotNull);

      expect(result.eyepieceFocalLabel, isNotEmpty);

    });



    test('recommends M42 without no-filter penalty on 90mm', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(id: 'm42', type: '발광성운'),

          objectType: ObjectType.emissionNebula,

          brightness: SurfaceBrightnessClass.veryBright,

          angularSize: AngularSizeClass.medium,

          widthArcmin: 72,
          heightArcmin: 72,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isTrue);
      expect(result.eyepiece, isNotNull);
      expect(result.screenFillPercent, greaterThan(0));
    });



    test('recommends M8 without no-filter penalty on 90mm', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(id: 'm8', type: '발광성운'),

          objectType: ObjectType.emissionNebula,

          brightness: SurfaceBrightnessClass.bright,

          angularSize: AngularSizeClass.large,

          widthArcmin: 60,
          heightArcmin: 60,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isTrue);
      expect(result.eyepiece, isNotNull);
      expect(result.screenFillPercent, greaterThan(0));
    });



    test('M20 gets moderate recommendation on 90mm', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(id: 'm20', type: '발광성운'),

          objectType: ObjectType.emissionNebula,

          brightness: SurfaceBrightnessClass.normal,

          angularSize: AngularSizeClass.medium,

          widthArcmin: 27,
          heightArcmin: 27,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isTrue);

      expect(result.starCount, lessThanOrEqualTo(3));

      expect(result.starCount, greaterThanOrEqualTo(2));

    });



    test('NGC2237 recommends central open cluster with 25mm', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(

            id: 'ngc2237',

            type: '발광성운',

            commonName: '장미 성운',

          ),

          objectType: ObjectType.emissionNebula,

          brightness: SurfaceBrightnessClass.dim,

          angularSize: AngularSizeClass.veryLarge,

          widthArcmin: 90,
          heightArcmin: 90,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isTrue);

      expect(result.reason, '중앙 산개성단 관측 추천');

      expect(result.starCount, lessThanOrEqualTo(3));

      expect(result.eyepiece?.focalLengthMm, 25);

    });



    test('blocks generic emission nebula not on no-filter whitelist', () {
      final result = scorer.bestRecommendation(
        context: contextFor(
          object: catalogObject(id: 'm17', type: '발광성운'),
          objectType: ObjectType.emissionNebula,
          brightness: SurfaceBrightnessClass.bright,
          angularSize: AngularSizeClass.medium,
          widthArcmin: 25,
          heightArcmin: 20,
        ),
        visualEquipment: [bcto90()],
      );

      expect(result, isNotNull);
      expect(result!.isRecommended, isFalse);
      expect(result.eyepiece, isNull);
      expect(result.reason, contains('필터 없이'));
    });

    test('blocks California Nebula on 90mm with no eyepiece', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(id: 'ngc1499', type: '발광성운'),

          objectType: ObjectType.emissionNebula,

          brightness: SurfaceBrightnessClass.dim,

          angularSize: AngularSizeClass.veryLarge,

          widthArcmin: 150,
          heightArcmin: 150,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result, isNotNull);

      expect(result!.isRecommended, isFalse);

      expect(result.eyepiece, isNull);

      expect(result.reason, contains('필터 없이'));

    });



    test('blocks NGC6334 on 90mm', () {

      final result = scorer.bestRecommendation(

        context: contextFor(

          object: catalogObject(id: 'ngc6334', type: '발광성운'),

          objectType: ObjectType.emissionNebula,

        ),

        visualEquipment: [bcto90()],

      );



      expect(result!.isRecommended, isFalse);

      expect(result.eyepiece, isNull);

    });

  });

}

