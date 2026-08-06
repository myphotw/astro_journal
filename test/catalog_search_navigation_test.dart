import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _object({
  required String id,
  required CatalogType catalog,
  int number = 1,
  bool isPrimary = true,
  String? primaryCatalogId,
  List<String> aliases = const [],
  String? searchKeywords,
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalog,
    name: id,
    type: '발광성운',
    objectType: '발광성운',
    constellation: '오리온자리',
    ra: '05h 35m',
    dec: '-05° 23\'',
    magnitude: '4.0',
    isPrimaryCatalog: isPrimary,
    primaryCatalogId: primaryCatalogId,
    aliases: aliases,
    searchKeywords: searchKeywords,
  );
}

void main() {
  group('CatalogSearchService.resolvePrimaryFromList', () {
    test('returns primary object for secondary search hit', () {
      final primary = _object(id: 'NGC6960', catalog: CatalogType.ngc);
      final secondary = _object(
        id: 'NGC6992',
        catalog: CatalogType.ngc,
        isPrimary: false,
        primaryCatalogId: 'NGC6960',
      );

      final resolved = CatalogSearchService.resolvePrimaryFromList(
        secondary,
        [primary, secondary],
      );

      expect(resolved.id, 'NGC6960');
    });
  });

  group('CatalogSearchService.mapToPrimaryCatalogResults', () {
    final sh2 = _object(
      id: 'Sh2-3',
      catalog: CatalogType.sh2,
      number: 3,
      aliases: const ['Green Ring', 'Green Ring Nebula'],
      searchKeywords: 'Sh2-3|Green Ring|RCW120',
    );
    final rcw120 = _object(
      id: 'RCW120',
      catalog: CatalogType.rcw,
      number: 120,
      isPrimary: false,
      primaryCatalogId: 'Sh2-3',
      aliases: const ['Green Ring Nebula'],
      searchKeywords: 'RCW 120|Green Ring Nebula|Sh2-3',
    );
    final ngc6818 = _object(
      id: 'NGC6818',
      catalog: CatalogType.ngc,
      number: 6818,
      aliases: const ['Little Gem Nebula, Green Mars Nebula'],
      searchKeywords: 'NGC 6818|Little Gem Nebula, Green Mars Nebula',
    );
    final all = [sh2, rcw120, ngc6818];

    test('maps secondary hits to primary catalog entries', () {
      final service = CatalogSearchService();

      final results = service.search('RCW120', all);

      expect(results.map((object) => object.id), ['Sh2-3']);
    });

    test('deduplicates multiple hits that resolve to same primary', () {
      final service = CatalogSearchService();

      final results = service.search('green', all);

      expect(results.map((object) => object.id), ['Sh2-3', 'NGC6818']);
    });

    test('drops hits without a primary catalog representative', () {
      final orphan = _object(
        id: 'RCW999',
        catalog: CatalogType.rcw,
        number: 999,
        isPrimary: false,
        primaryCatalogId: 'MissingPrimary',
        searchKeywords: 'RCW 999',
      );

      final mapped = CatalogSearchService.mapToPrimaryCatalogResults(
        [orphan],
        [...all, orphan],
      );

      expect(mapped, isEmpty);
    });
  });
}
