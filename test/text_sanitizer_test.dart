import 'package:astro_journal/core/utils/text_sanitizer.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextSanitizer', () {
    test('stripHanzi removes CJK from mixed alias text', () {
      expect(
        TextSanitizer.stripHanzi('Crab Nebula 蟹状星云'),
        'Crab Nebula',
      );
    });

    test('sanitizeList drops Hanzi-only aliases', () {
      expect(
        TextSanitizer.sanitizeList(['Orion Nebula', '猎户座大星云', 'M42']),
        ['Orion Nebula', 'M42'],
      );
    });
  });

  group('CatalogObject Hanzi sanitization', () {
    test('fromMap strips Hanzi from aliases and text fields', () {
      final object = CatalogObject.fromMap({
        'id': 'M1',
        'num': 1,
        'catalog': 'messier',
        'name': 'Crab Nebula 蟹状星云',
        'type': '성운',
        'constellation': '황소자리',
        'ra': '-',
        'dec': '-',
        'mag': '-',
        'aliases_json': '["Crab Nebula","蟹状星云","Taurus A"]',
        'cross_catalog_refs_json': '["NGC 1952","超新星遗迹"]',
        'description': '펄서 脉冲星 구름',
      });

      expect(object.displayAliases, ['Crab Nebula', 'Taurus A']);
      expect(object.displayCrossCatalogRefs, ['NGC 1952']);
      expect(object.name, 'Crab Nebula');
      expect(object.displayDescription, '펄서 구름');
      expect(TextSanitizer.containsHanzi(object.name), isFalse);
    });
  });
}
