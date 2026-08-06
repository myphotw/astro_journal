import 'package:astro_journal/core/utils/catalog_reference_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogReferenceClassifier', () {
    test('treats human names as aliases', () {
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('Butterfly Cluster'),
        isFalse,
      );
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('Orion Nebula'),
        isFalse,
      );
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('안드로메다 은하'),
        isFalse,
      );
    });

    test('treats catalog identifiers as cross references', () {
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('NGC 6405'),
        isTrue,
      );
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('MWSC 2661'),
        isTrue,
      );
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('Sh2-101'),
        isTrue,
      );
      expect(
        CatalogReferenceClassifier.isCrossCatalogReference('Caldwell 33'),
        isTrue,
      );
    });

    test('splits mixed values', () {
      final split = CatalogReferenceClassifier.split([
        'Butterfly Cluster',
        'MWSC 2661',
        'NGC 6405',
      ]);
      expect(split.aliases, ['Butterfly Cluster']);
      expect(split.crossCatalogRefs, ['MWSC 2661', 'NGC 6405']);
    });
  });
}
