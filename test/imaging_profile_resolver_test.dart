import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/imaging_difficulty.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/exposure_policy.dart';
import 'package:astro_journal/services/imaging_profile_resolver.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImagingProfileResolver', () {
    const resolver = ImagingProfileResolver();
    const policy = ExposurePolicy();
    const catalogBortle = 8;

    CatalogObject buildObject({
      required String id,
      required String type,
      String? objectType,
      String magnitude = '-',
      String? angularSize,
      List<String> tags = const [],
    }) {
      return CatalogObject(
        id: id,
        number: 42,
        catalog: CatalogType.messier,
        name: id.toUpperCase(),
        type: type,
        objectType: objectType,
        constellation: 'Test',
        ra: '5h 35m',
        dec: '-05° 23m',
        magnitude: magnitude,
        angularSize: angularSize,
        tags: tags,
      );
    }

    ({int min, int rec}) exposureFor(CatalogObject object) {
      final profile = resolver.resolve(
        object,
        ObjectType.fromLabel(object.objectType ?? object.type),
      );
      return (
        min: policy
            .calculateMinimumExposure(bortle: catalogBortle, profile: profile)
            .inMinutes,
        rec: policy
            .calculateRecommendedExposure(bortle: catalogBortle, profile: profile)
            .inMinutes,
      );
    }

    test('M42 and NGC7000 share emission type but differ in brightness', () {
      final m42 = buildObject(
        id: 'm42',
        type: '발광성운',
        objectType: '발광성운',
        magnitude: '4.0',
        angularSize: "85' × 60'",
      );
      final ngc7000 = buildObject(
        id: 'ngc7000',
        type: '발광성운',
        objectType: '발광성운',
        magnitude: '-',
        angularSize: "120' × 100'",
      );

      final m42Profile = resolver.resolve(m42, ObjectType.emissionNebula);
      final ngcProfile = resolver.resolve(ngc7000, ObjectType.emissionNebula);

      expect(m42Profile.surfaceBrightnessClass, SurfaceBrightnessClass.veryBright);
      expect(
        ngcProfile.surfaceBrightnessClass,
        isIn([
          SurfaceBrightnessClass.dim,
          SurfaceBrightnessClass.veryDim,
        ]),
      );

      final m42Exposure = exposureFor(m42);
      final ngcExposure = exposureFor(ngc7000);
      expect(m42Exposure.min, lessThan(ngcExposure.min));
      expect(m42Exposure.rec, lessThan(ngcExposure.rec));
    });

    test('representative emission nebulae', () {
      final m42 = exposureFor(
        buildObject(
          id: 'm42',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '4.0',
          angularSize: "85' × 60'",
        ),
      );
      final m8 = exposureFor(
        buildObject(
          id: 'm8',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '5.8',
          angularSize: "90' × 40'",
        ),
      );
      final m20 = exposureFor(
        buildObject(
          id: 'm20',
          type: '복합성운',
          objectType: '복합성운',
          magnitude: '6.3',
          angularSize: "28' × 30'",
        ),
      );

      expect(m42.min, inInclusiveRange(15, 30));
      expect(m42.rec, inInclusiveRange(30, 60));
      expect(m8.min, inInclusiveRange(20, 35));
      expect(m20.min, inInclusiveRange(22, 35));
    });

    test('representative galaxies differentiate by magnitude', () {
      final m31 = exposureFor(
        buildObject(id: 'm31', type: '은하', magnitude: '3.4'),
      );
      final m101 = exposureFor(
        buildObject(id: 'm101', type: '은하', magnitude: '7.9'),
      );

      expect(m31.min, lessThan(m101.min));
      expect(m31.min, inInclusiveRange(35, 55));
      expect(m101.min, greaterThanOrEqualTo(60));
    });

    test('M16 is brighter than NGC7000 but dimmer than M42', () {
      final m16 = exposureFor(
        buildObject(
          id: 'm16',
          type: '성운+성단',
          objectType: '성운+성단',
          magnitude: '6.0',
          angularSize: "7'",
        ),
      );
      final m42 = exposureFor(
        buildObject(
          id: 'm42',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '4.0',
          angularSize: "85' × 60'",
        ),
      );
      final ngc7000 = exposureFor(
        buildObject(
          id: 'ngc7000',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '-',
          angularSize: "120' × 100'",
        ),
      );

      expect(m16.min, greaterThan(m42.min));
      expect(m16.min, lessThan(ngc7000.min));
      expect(m16.min, inInclusiveRange(35, 55));
    });

    test('planetary nebulae use bright profiles', () {
      final m57 = resolver.resolve(
        buildObject(
          id: 'm57',
          type: '행성상성운',
          objectType: '행성상성운',
          magnitude: '8.8',
        ),
        ObjectType.planetaryNebula,
      );

      expect(m57.surfaceBrightnessClass, SurfaceBrightnessClass.bright);
      expect(m57.imagingDifficulty, ImagingDifficulty.easy);
    });
  });

  group('ObjectImagingProfileProvider', () {
    const provider = ObjectImagingProfileProvider();

    test('infers metadata-driven profile for M42', () {
      final profile = provider.profileFor(
        CatalogObject(
          id: 'm42',
          number: 42,
          catalog: CatalogType.messier,
          name: '오리온 성운',
          type: '성운',
          objectType: '발광성운',
          constellation: '오리온',
          ra: '05h 35m',
          dec: '-05°23m',
          magnitude: '4.0',
          angularSize: "85' × 60'",
        ),
      );

      expect(profile.objectType, ObjectType.emissionNebula);
      expect(profile.surfaceBrightnessClass, SurfaceBrightnessClass.veryBright);
      expect(profile.baseExposureMinutes, 20);
    });
  });
}
