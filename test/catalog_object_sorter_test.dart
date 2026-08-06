import 'package:astro_journal/core/constants/catalog_sort_order.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_object_sorter.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _object({
  required String id,
  required int number,
  required CatalogType catalog,
  String? name,
  String? commonName,
  String? objectType,
  String constellation = '오리온자리',
  bool isFeatured = false,
  int displayPriority = 9999,
  String? suffix,
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalog,
    name: name ?? id,
    type: objectType ?? '발광성운',
    commonName: commonName,
    objectType: objectType ?? '발광성운',
    constellation: constellation,
    ra: '05h 35m',
    dec: '-05° 23\'',
    magnitude: '4.0',
    isFeatured: isFeatured,
    displayPriority: displayPriority,
    suffix: suffix,
  );
}

void main() {
  group('CatalogObjectSorter', () {
    test('default order keeps messier number and featured priority', () {
      final objects = [
        _object(id: 'M42', number: 42, catalog: CatalogType.messier),
        _object(id: 'M1', number: 1, catalog: CatalogType.messier),
        _object(
          id: 'NGC7000',
          number: 7000,
          catalog: CatalogType.ngc,
          isFeatured: true,
          displayPriority: 10,
        ),
        _object(
          id: 'NGC1',
          number: 1,
          catalog: CatalogType.ngc,
          displayPriority: 100,
        ),
      ];

      final sorted = CatalogObjectSorter.sort(
        objects,
        CatalogSortOrder.defaultOrder,
      );

      expect(sorted.map((object) => object.id).toList(), [
        'M1',
        'M42',
        'NGC7000',
        'NGC1',
      ]);
    });

    test('name sort orders by display name', () {
      final objects = [
        _object(
          id: 'M42',
          number: 42,
          catalog: CatalogType.messier,
          commonName: '오리온 대성운',
        ),
        _object(
          id: 'M1',
          number: 1,
          catalog: CatalogType.messier,
          commonName: '게성운',
        ),
        _object(
          id: 'NGC7000',
          number: 7000,
          catalog: CatalogType.ngc,
          commonName: '북아메리카 성운',
        ),
      ];

      final sorted = CatalogObjectSorter.sort(objects, CatalogSortOrder.nameAsc);

      expect(sorted.map((object) => object.id).toList(), [
        'M1',
        'NGC7000',
        'M42',
      ]);
    });

    test('name sort uses natural order for catalog designations', () {
      final objects = [
        _object(
          id: 'NGC101',
          number: 101,
          catalog: CatalogType.ngc,
          objectType: '기타',
        ),
        _object(
          id: 'NGC1',
          number: 1,
          catalog: CatalogType.ngc,
          objectType: '기타',
        ),
        _object(
          id: 'NGC10',
          number: 10,
          catalog: CatalogType.ngc,
          objectType: '기타',
        ),
        _object(
          id: 'NGC2',
          number: 2,
          catalog: CatalogType.ngc,
          objectType: '기타',
        ),
      ];

      final sorted = CatalogObjectSorter.sort(objects, CatalogSortOrder.nameAsc);

      expect(sorted.map((object) => object.id).toList(), [
        'NGC1',
        'NGC2',
        'NGC10',
        'NGC101',
      ]);
    });

    test('compareNatural orders embedded numbers numerically', () {
      expect(CatalogObjectSorter.compareNatural('M1', 'M2'), lessThan(0));
      expect(CatalogObjectSorter.compareNatural('M2', 'M10'), lessThan(0));
      expect(CatalogObjectSorter.compareNatural('M10', 'M101'), lessThan(0));
      expect(CatalogObjectSorter.compareNatural('NGC 2', 'NGC 10'), lessThan(0));
    });

    test('catalog number sort orders by catalog kind then number', () {
      final objects = [
        _object(id: 'NGC10', number: 10, catalog: CatalogType.ngc),
        _object(id: 'M5', number: 5, catalog: CatalogType.messier),
        _object(id: 'NGC2', number: 2, catalog: CatalogType.ngc),
      ];

      final sorted = CatalogObjectSorter.sort(
        objects,
        CatalogSortOrder.catalogNumber,
      );

      expect(sorted.map((object) => object.id).toList(), [
        'M5',
        'NGC2',
        'NGC10',
      ]);
    });
  });
}
