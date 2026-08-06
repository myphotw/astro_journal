import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_metadata_enricher.dart';
import 'package:astro_journal/services/equipment/representative_framing_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const enricher = CatalogMetadataEnricher();
  const resolver = RepresentativeFramingResolver();

  CatalogObject messierObject({
    required String id,
    required int number,
    String type = '성운',
  }) {
    return CatalogObject(
      id: id,
      number: number,
      catalog: CatalogType.messier,
      name: id,
      type: type,
      constellation: 'Test',
      ra: '18h 18m',
      dec: "-13°47'",
      magnitude: '6.0',
    );
  }

  group('RepresentativeFramingResolver', () {
    test('M16 catalog 7 arcmin vs framing 65x50', () {
      final catalog = enricher.enrich(messierObject(id: 'M16', number: 16));
      expect(catalog.angularSize, "7'");

      final framing = resolver.resolve(catalog);
      expect(framing.widthArcmin, 65);
      expect(framing.heightArcmin, 50);
    });

    test('M13 without framing override falls back to catalog angular size', () {
      final catalog = enricher.enrich(messierObject(id: 'M13', number: 13));
      expect(catalog.angularSize, "20'");

      final framing = resolver.resolve(catalog);
      expect(framing.widthArcmin, 20);
      expect(framing.heightArcmin, 20);
    });

    test('M31 uses explicit framing override matching catalog dimensions', () {
      final catalog = enricher.enrich(messierObject(id: 'M31', number: 31));
      final framing = resolver.resolve(catalog);
      expect(framing.widthArcmin, 190);
      expect(framing.heightArcmin, 60);
    });
  });

}
