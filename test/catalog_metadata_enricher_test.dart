import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_metadata_enricher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const enricher = CatalogMetadataEnricher();

  const m42 = CatalogObject(
    id: 'M42',
    number: 42,
    catalog: CatalogType.messier,
    name: '오리온 대성운',
    type: '성운',
    constellation: '오리온',
    ra: '05h 35m 17s',
    dec: '-05° 23\'',
    magnitude: '4.0',
  );

  group('CatalogMetadataEnricher', () {
    test('Messier 대상은 크기·설명·계절을 채운다', () {
      final enriched = enricher.enrich(m42);

      expect(enriched.angularSize, "85' × 60'");
      expect(enriched.description, contains('오리온'));
      expect(enriched.bestSeason, isNotNull);
      expect(enriched.peakMonth, isNotNull);
    });

    test('RA 없는 사용자 추가 항목은 설명만 생성한다', () {
      const custom = CatalogObject(
        id: 'custom-1',
        number: 1,
        catalog: CatalogType.ngc,
        name: 'Custom Nebula',
        type: '성운',
        constellation: '오리온',
        ra: '',
        dec: '',
        magnitude: '-',
      );

      final enriched = enricher.enrich(custom);

      expect(enriched.bestSeason, isNull);
      expect(enriched.description, contains('오리온'));
      expect(enriched.angularSize, isNotNull);
    });

    test('태양계 대상은 계절·크기 추정을 생략한다', () {
      const jupiter = CatalogObject(
        id: 'jupiter',
        number: 5,
        catalog: CatalogType.solar,
        name: '목성',
        type: '행성',
        constellation: '-',
        ra: '-',
        dec: '-',
        magnitude: '-2.0',
      );

      final enriched = enricher.enrich(jupiter);

      expect(enriched.bestSeason, isNull);
      expect(enriched.angularSize, isNull);
      expect(enriched.description, contains('목성'));
    });
  });
}
