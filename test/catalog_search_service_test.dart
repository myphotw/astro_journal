import 'dart:convert';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogSearchService service;

  final sampleCatalog = [
    const CatalogObject(
      id: 'M27',
      number: 27,
      catalog: CatalogType.messier,
      name: '아령 성운',
      type: '성운',
      constellation: '여우',
      ra: '18h 33m',
      dec: '-22°26',
      magnitude: '7.4',
    ),
    const CatalogObject(
      id: 'NGC253',
      number: 253,
      catalog: CatalogType.ngc,
      name: '은하수 손가락',
      type: '은하',
      constellation: '조각가',
      ra: '00h 47m',
      dec: '-25°17',
      magnitude: '7.1',
    ),
    const CatalogObject(
      id: 'IC434',
      number: 434,
      catalog: CatalogType.ic,
      name: '말머리 성운',
      type: '성운',
      constellation: '오리온',
      ra: '05h 41m',
      dec: '-02°24',
      magnitude: '-',
    ),
    const CatalogObject(
      id: 'C33',
      number: 33,
      catalog: CatalogType.caldwell,
      name: '이중 성단',
      type: '산개성단',
      constellation: '영웅',
      ra: '02h 19m',
      dec: '+57°08',
      magnitude: '3.7',
    ),
    const CatalogObject(
      id: 'Sh2-155',
      number: 155,
      catalog: CatalogType.sh2,
      name: '동굴 성운',
      type: '성운',
      constellation: '세페우스',
      ra: '22h 56m',
      dec: '+62°37',
      magnitude: '-',
    ),
  ];

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/catalog/search_aliases.json') {
        return ByteData.view(
          utf8.encode('''
{
  "M27": ["Dumbbell Nebula", "Dumbbell"],
  "NGC6853": ["Dumbbell Nebula"]
}
''').buffer,
        );
      }
      return null;
    });
    await CatalogSearchService.loadGlobalAliases();
  });

  setUp(() {
    service = CatalogSearchService();
  });

  group('CatalogSearchService.resolveTarget', () {
    test('Messier M27', () {
      final result = service.resolveTarget('M27', sampleCatalog);
      expect(result?.id, 'M27');
    });

    test('Messier with space M 27', () {
      final result = service.resolveTarget('M 27', sampleCatalog);
      expect(result?.id, 'M27');
    });

    test('NGC 253', () {
      final result = service.resolveTarget('NGC 253', sampleCatalog);
      expect(result?.id, 'NGC253');
    });

    test('IC434', () {
      final result = service.resolveTarget('IC434', sampleCatalog);
      expect(result?.id, 'IC434');
    });

    test('Caldwell C33', () {
      final result = service.resolveTarget('C33', sampleCatalog);
      expect(result?.id, 'C33');
    });

    test('Caldwell long form', () {
      final result = service.resolveTarget('Caldwell 33', sampleCatalog);
      expect(result?.id, 'C33');
    });

    test('Sh2-155', () {
      final result = service.resolveTarget('Sh2-155', sampleCatalog);
      expect(result?.id, 'Sh2-155');
    });

    test('Sh2 without hyphen', () {
      final result = service.resolveTarget('Sh2 155', sampleCatalog);
      expect(result?.id, 'Sh2-155');
    });

    test('returns null for unknown target', () {
      final result = service.resolveTarget('M999', sampleCatalog);
      expect(result, isNull);
    });
  });

  group('CatalogSearchService.search', () {
    test('finds Messier by id', () {
      final results = service.search('M27', sampleCatalog);
      expect(results.length, 1);
      expect(results.first.id, 'M27');
    });

    test('M1 search does not match M10 or M11', () {
      final messierCatalog = [
        const CatalogObject(
          id: 'M1',
          number: 1,
          catalog: CatalogType.messier,
          name: '게 성운',
          type: '성운',
          constellation: '황소자리',
          ra: '05h 34m',
          dec: '+22°01',
          magnitude: '8.4',
        ),
        const CatalogObject(
          id: 'M10',
          number: 10,
          catalog: CatalogType.messier,
          name: '구상성단',
          type: '구상성단',
          constellation: '오phiuchus',
          ra: '16h 57m',
          dec: '-04°06',
          magnitude: '6.6',
        ),
        const CatalogObject(
          id: 'M11',
          number: 11,
          catalog: CatalogType.messier,
          name: '산개성단',
          type: '산개성단',
          constellation: '독수리자리',
          ra: '18h 51m',
          dec: '-06°16',
          magnitude: '6.3',
        ),
      ];

      final results = service.search('M1', messierCatalog);
      expect(results.length, 1);
      expect(results.first.id, 'M1');
    });

    test('finds Sh2 objects', () {
      final results = service.search('Sh2', sampleCatalog);
      expect(results.any((o) => o.catalog == CatalogType.sh2), isTrue);
    });

    test('finds by English alias Dumbbell', () {
      final results = service.search('Dumbbell', sampleCatalog);
      expect(results.any((o) => o.id == 'M27'), isTrue);
    });

    test('finds by Korean name', () {
      final results = service.search('아령', sampleCatalog);
      expect(results.any((o) => o.id == 'M27'), isTrue);
    });
  });
}
