import 'package:astro_journal/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeocodingService.approximateRegionName', () {
    test('combines level1 and level2', () {
      expect(
        GeocodingService.approximateRegionName(
          level1: '부산광역시',
          level2: '해운대구',
        ),
        '부산광역시 해운대구',
      );
    });

    test('falls back to level2 only', () {
      expect(
        GeocodingService.approximateRegionName(level2: '수원시'),
        '수원시',
      );
    });

    test('falls back to level1', () {
      expect(
        GeocodingService.approximateRegionName(level1: '강원특별자치도'),
        '강원특별자치도',
      );
    });
  });
}
