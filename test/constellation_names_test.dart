import 'package:astro_journal/core/constants/constellation_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConstellationNames', () {
    test('축약 표기를 정규 한국어 명칭으로 변환한다', () {
      expect(ConstellationNames.normalize('리라'), '리라자리');
      expect(ConstellationNames.normalize('거문고'), '거문고자리');
      expect(ConstellationNames.normalize('오리온'), '오리온자리');
      expect(ConstellationNames.normalize('쌍둥이'), '쌍둥이자리');
    });

    test('이미 정규 명칭이면 그대로 유지한다', () {
      expect(ConstellationNames.normalize('백조자리'), '백조자리');
      expect(ConstellationNames.normalize('-'), '-');
    });

    test('검색용 축약 별칭을 제공한다', () {
      final terms = ConstellationNames.searchTerms('오리온자리');
      expect(terms, contains('오리온자리'));
      expect(terms, contains('오리온'));
    });
  });
}
