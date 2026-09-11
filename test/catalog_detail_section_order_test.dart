import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog detail keeps the compact imaging section order', () {
    final source = File(
      'lib/features/catalog/view/catalog_detail_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    final currentSite = source.indexOf('CatalogExposureGuidanceSection(');
    final multiNight = source.indexOf('MultiNightFramingSection(');
    final equipment = source.indexOf('EquipmentRecommendationSection(');
    final siteComparison = source.indexOf(
      'CatalogImagingAvailabilitySection(',
    );

    expect(currentSite, greaterThan(0));
    expect(multiNight, greaterThan(currentSite));
    expect(equipment, greaterThan(multiNight));
    expect(siteComparison, greaterThan(equipment));
  });
}
