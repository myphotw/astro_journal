import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/constants/surface_brightness_class.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/object_imaging_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObjectImagingProfileProvider', () {
    const provider = ObjectImagingProfileProvider();

    CatalogObject buildObject({
      required String id,
      required String type,
      String? objectType,
      String magnitude = '5.0',
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

    test('returns metadata-driven profile for M42', () {
      final profile = provider.profileFor(
        buildObject(
          id: 'm42',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '4.0',
          angularSize: "85' × 60'",
        ),
      );

      expect(profile.objectType, ObjectType.emissionNebula);
      expect(profile.surfaceBrightnessClass, SurfaceBrightnessClass.veryBright);
    });

    test('returns galaxy type for M87', () {
      final profile = provider.profileFor(
        buildObject(id: 'm87', type: '은하'),
      );

      expect(profile.objectType, ObjectType.galaxy);
    });

    test('resolves milky way from tag', () {
      final profile = provider.profileFor(
        buildObject(
          id: 'custom1',
          type: '기타',
          tags: ['은하수'],
        ),
      );

      expect(profile.objectType, ObjectType.milkyWay);
    });

    test('NGC7000 is dimmer than M42 within emission nebula type', () {
      final m42 = provider.profileFor(
        buildObject(
          id: 'm42',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '4.0',
          angularSize: "85' × 60'",
        ),
      );
      final ngc7000 = provider.profileFor(
        buildObject(
          id: 'ngc7000',
          type: '발광성운',
          objectType: '발광성운',
          magnitude: '-',
          angularSize: "120' × 100'",
        ),
      );

      expect(m42.objectType, ObjectType.emissionNebula);
      expect(ngc7000.objectType, ObjectType.emissionNebula);
      expect(
        m42.surfaceBrightnessClass.tierIndex,
        lessThan(ngc7000.surfaceBrightnessClass.tierIndex),
      );
    });
  });
}
