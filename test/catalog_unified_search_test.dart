import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSearchService service;

  const ic434 = CatalogObject(
    id: 'IC434',
    number: 434,
    catalog: CatalogType.ic,
    name: '말머리 성운',
    commonName: '말머리 성운',
    objectType: '발광성운',
    type: '발광성운',
    constellation: '오리온',
    ra: '05h 41m',
    dec: '-02°24',
    magnitude: '-',
    seestarSupported: true,
    aliases: ['Horsehead Nebula', '말머리'],
  );

  const ngc7000 = CatalogObject(
    id: 'NGC7000',
    number: 7000,
    catalog: CatalogType.ngc,
    name: '북아메리카 성운',
    commonName: '북아메리카 성운',
    objectType: '발광성운',
    type: '발광성운',
    constellation: '백조',
    ra: '20h 58m',
    dec: '+44°20',
    magnitude: '-',
    seestarSupported: true,
    aliases: ['Caldwell 20', 'C20', '북아메리카'],
  );

  const ic1805 = CatalogObject(
    id: 'IC1805',
    number: 1805,
    catalog: CatalogType.ic,
    name: '하트 성운',
    commonName: '하트 성운',
    objectType: '발광성운',
    type: '발광성운',
    constellation: '카시오페아',
    ra: '02h 32m',
    dec: '+61°27',
    magnitude: '-',
    seestarSupported: true,
    aliases: ['Caldwell 31', '하트'],
  );

  const ngc6960 = CatalogObject(
    id: 'NGC6960',
    number: 6960,
    catalog: CatalogType.ngc,
    name: '서쪽 베일 성운',
    commonName: '서쪽 베일 성운',
    objectType: '초신성잔해',
    type: '초신성잔해',
    constellation: '백조',
    ra: '20h 45m',
    dec: '+30°35',
    magnitude: '-',
    seestarSupported: true,
    aliases: ['베일', 'Veil Nebula'],
  );

  const ngc6992 = CatalogObject(
    id: 'NGC6992',
    number: 6992,
    catalog: CatalogType.ngc,
    name: '동쪽 베일 성운',
    commonName: '동쪽 베일 성운',
    objectType: '초신성잔해',
    type: '초신성잔해',
    constellation: '백조',
    ra: '20h 56m',
    dec: '+31°43',
    magnitude: '-',
    seestarSupported: true,
    aliases: ['베일', 'Veil Nebula'],
  );

  final catalog = [ic434, ngc7000, ic1805, ngc6960, ngc6992];

  setUp(() {
    service = CatalogSearchService();
  });

  test('C20 resolves to NGC7000', () {
    expect(service.resolveTarget('C20', catalog)?.id, 'NGC7000');
  });

  test('말머리 search finds IC434', () {
    final results = service.search('말머리', catalog);
    expect(results.any((o) => o.id == 'IC434'), isTrue);
  });

  test('하트 search finds IC1805', () {
    final results = service.search('하트', catalog);
    expect(results.any((o) => o.id == 'IC1805'), isTrue);
  });

  test('베일 search returns multiple veil nebula parts', () {
    final results = service.search('베일', catalog);
    expect(results.where((o) => o.id.startsWith('NGC69')).length, greaterThan(1));
  });
}
