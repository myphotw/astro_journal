import 'package:astro_journal/core/utils/catalog_reference_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves spaced and compact catalog references', () {
    final lookup = CatalogReferenceResolver.buildLookup([
      'Sh2-3',
      'RCW120',
      'NGC6960',
      'M1',
    ]);

    expect(CatalogReferenceResolver.resolve('Sh2 3', lookup), 'Sh2-3');
    expect(CatalogReferenceResolver.resolve('RCW 120', lookup), 'RCW120');
    expect(CatalogReferenceResolver.resolve('NGC 6960', lookup), 'NGC6960');
    expect(CatalogReferenceResolver.resolve('M1', lookup), 'M1');
  });
}
