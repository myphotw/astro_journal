import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_display_name_resolver.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _object({
  required String id,
  List<String> aliases = const [],
  String? commonName,
  String name = 'name',
  String type = '발광성운',
  CatalogType catalog = CatalogType.messier,
  int? number,
}) {
  return CatalogObject(
    id: id,
    number: number ?? int.tryParse(id.replaceAll(RegExp(r'\D'), '')) ?? 1,
    catalog: catalog,
    name: name,
    type: type,
    commonName: commonName,
    objectType: type,
    aliases: aliases,
    constellation: '오리온자리',
    ra: '05h 35m',
    dec: '-05° 23\'',
    magnitude: '4.0',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CatalogSearchService.loadGlobalAliases();
    await CatalogDisplayNameResolver.load();
  });

  test('prefers Korean alias over common name', () {
    final object = _object(
      id: 'M42',
      commonName: 'M42',
      aliases: const ['오리온 대성운'],
    );

    expect(CatalogDisplayNameResolver.resolve(object), '오리온 대성운');
  });

  test('translates English alias via dictionary', () {
    final object = _object(
      id: 'M1',
      commonName: 'M1',
      aliases: const ['Crab Nebula'],
      type: '초신성잔해',
    );

    expect(CatalogDisplayNameResolver.resolve(object), '게성운');
  });

  test('translates Christmas Tree Cluster alias', () {
    final object = _object(
      id: 'NGC2264',
      catalog: CatalogType.ngc,
      commonName: 'NGC 2264',
      name: 'NGC 2264',
      aliases: const ['Christmas Tree Cluster'],
      type: '기타',
    );

    expect(
      CatalogDisplayNameResolver.resolve(object),
      '크리스마스 트리 성단',
    );
  });

  test('does not use 기타 as display name fallback', () {
    final object = _object(
      id: 'NGC9999',
      catalog: CatalogType.ngc,
      commonName: 'NGC 9999',
      name: 'NGC 9999',
      type: '기타',
    );

    expect(CatalogDisplayNameResolver.resolve(object), isNull);
  });

  test('dictionary entry count is populated', () {
    expect(CatalogDisplayNameResolver.dictionaryEntryCount, greaterThan(30));
  });
}
