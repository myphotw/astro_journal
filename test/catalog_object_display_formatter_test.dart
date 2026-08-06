import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/formatters/catalog_object_display_formatter.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_display_name_resolver.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _object({
  required String id,
  required int number,
  required CatalogType catalog,
  required String name,
  required String type,
  String? commonName,
  String? objectType,
  List<String> aliases = const [],
}) {
  return CatalogObject(
    id: id,
    number: number,
    catalog: catalog,
    name: name,
    type: type,
    commonName: commonName,
    objectType: objectType,
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

  group('CatalogObjectDisplayFormatter', () {
    test('catalogTitle always returns catalog designation', () {
      final object = _object(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        commonName: '오리온 대성운',
        objectType: '발광성운',
      );

      expect(
        CatalogObjectDisplayFormatter.catalogTitle(object),
        'M42',
      );
    });

    test('Case 1: distinct display name shows name(type)', () {
      final m1 = _object(
        id: 'M1',
        number: 1,
        catalog: CatalogType.messier,
        name: 'M1',
        type: '초신성잔해',
        objectType: '초신성잔해',
        aliases: const ['Crab Nebula'],
      );
      final m42 = _object(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        commonName: '오리온 대성운',
        objectType: '발광성운',
      );
      final ngc7000 = _object(
        id: 'NGC7000',
        number: 7000,
        catalog: CatalogType.ngc,
        name: 'NGC 7000',
        type: '발광성운',
        commonName: '북아메리카 성운',
        objectType: '발광성운',
      );
      final sh2298 = _object(
        id: 'Sh2-298',
        number: 298,
        catalog: CatalogType.sh2,
        name: 'Sh2-298',
        type: '발광성운',
        objectType: '발광성운',
        aliases: const ["Thor's Helmet"],
      );

      expect(CatalogObjectDisplayFormatter.subtitle(m1), '게성운(초신성잔해)');
      expect(CatalogObjectDisplayFormatter.subtitle(m42), '오리온 대성운(발광성운)');
      expect(
        CatalogObjectDisplayFormatter.subtitle(ngc7000),
        '북아메리카 성운(발광성운)',
      );
      expect(
        CatalogObjectDisplayFormatter.subtitle(sh2298),
        '토르의 헬멧(발광성운)',
      );
    });

    test('Case 2: display name equals catalog name shows type only', () {
      final sh2196 = _object(
        id: 'Sh2-196',
        number: 196,
        catalog: CatalogType.sh2,
        name: 'Sh2-196',
        type: '구상성단',
        commonName: 'Sh2-196',
        objectType: '구상성단',
      );

      expect(sh2196.uiDisplayName, '구상성단');
      expect(CatalogObjectDisplayFormatter.subtitle(sh2196), '구상성단');
    });

    test('Case 3: display name equals object type shows display name only', () {
      final m3 = _object(
        id: 'M3',
        number: 3,
        catalog: CatalogType.messier,
        name: 'M3',
        type: '구상성단',
        commonName: '구상성단',
        objectType: '구상성단',
      );

      expect(m3.uiDisplayName, '구상성단');
      expect(CatalogObjectDisplayFormatter.subtitle(m3), '구상성단');
    });

    test('Case 4: missing display name shows type only', () {
      final m56 = _object(
        id: 'M56',
        number: 56,
        catalog: CatalogType.messier,
        name: 'M56',
        type: '구상성단',
        objectType: '구상성단',
      );

      expect(m56.uiDisplayName, '구상성단');
      expect(CatalogObjectDisplayFormatter.subtitle(m56), '구상성단');
    });

    test('labelsMatch ignores spaces and case', () {
      expect(CatalogObjectDisplayFormatter.labelsMatch('NGC 7000', 'ngc7000'), isTrue);
      expect(CatalogObjectDisplayFormatter.labelsMatch('Sh2-196', 'SH2-196'), isTrue);
    });

    test('listSubtitle appends constellation', () {
      final object = _object(
        id: 'M42',
        number: 42,
        catalog: CatalogType.messier,
        name: 'M42',
        type: '발광성운',
        commonName: '오리온 대성운',
        objectType: '발광성운',
      );

      expect(
        CatalogObjectDisplayFormatter.listSubtitle(object),
        '오리온 대성운(발광성운) · 오리온자리',
      );
    });

    test('formatDistanceLy applies thousands separators', () {
      expect(
        CatalogObjectDisplayFormatter.formatDistanceLy(7200),
        '7,200 광년',
      );
      expect(
        CatalogObjectDisplayFormatter.formatDistanceLy(2540000),
        '2,540,000 광년',
      );
      expect(
        CatalogObjectDisplayFormatter.formatDistanceLy(8.6),
        '8.6 광년',
      );
      expect(CatalogObjectDisplayFormatter.formatDistanceLy(null), isNull);
      expect(CatalogObjectDisplayFormatter.formatDistanceLy(0), isNull);
    });

    test('formatAngularSize strips trailing zeros', () {
      expect(
        CatalogObjectDisplayFormatter.formatAngularSize("36.00'"),
        '36′',
      );
      expect(
        CatalogObjectDisplayFormatter.formatAngularSize("35.50'"),
        '35.5′',
      );
      expect(
        CatalogObjectDisplayFormatter.formatAngularSize("190.00' × 60.00'"),
        '190′ × 60′',
      );
    });
  });
}
