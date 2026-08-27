import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/features/photo_first/widgets/registration_target_search_panel.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(CatalogSearchService.invalidateIndex);

  testWidgets('selecting a search result dismisses focus and selects target', (
    tester,
  ) async {
    const target = CatalogObject(
      id: 'M42',
      number: 42,
      catalog: CatalogType.messier,
      name: 'M42',
      commonName: 'Orion Nebula',
      type: 'Nebula',
      constellation: 'Ori',
      ra: '05h 35m',
      dec: '-05d 23m',
      magnitude: '4.0',
    );
    CatalogObject? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RegistrationTargetSearchPanel(
              allObjects: const [target],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'M42');
    await tester.pump(const Duration(milliseconds: 200));
    final focusNode = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byType(ListTile));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(selected?.id, 'M42');
  });

  testWidgets('record-only comet can be selected as a registration target', (
    tester,
  ) async {
    const halley = CatalogObject(
      id: 'solar_11',
      number: 11,
      catalog: CatalogType.solar,
      name: '핼리 혜성',
      commonName: '핼리 혜성',
      type: '혜성',
      objectType: '혜성',
      constellation: '-',
      ra: '-',
      dec: '-',
      magnitude: '-',
      aliases: ['1P/Halley', "Halley's Comet", 'Halley'],
      tags: ['태양계', '혜성', 'record_only', 'dynamic_ephemeris'],
    );
    CatalogObject? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RegistrationTargetSearchPanel(
              allObjects: const [halley],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Halley');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(ListTile));
    await tester.pump();

    expect(selected?.id, 'solar_11');
    expect(selected?.catalog, CatalogType.solar);
    expect(selected?.name, '핼리 혜성');
    expect(selected?.ra, '-');
    expect(selected?.dec, '-');
  });
}
