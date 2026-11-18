import 'dart:ui' as ui;

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/object_type.dart';
import 'package:astro_journal/core/theme/app_theme.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/shared/widgets/catalog_object_card.dart';
import 'package:astro_journal/shared/widgets/catalog_object_image.dart';
import 'package:astro_journal/shared/widgets/catalog_object_symbol.dart';
import 'package:astro_journal/shared/widgets/inline_catalog_search_results.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogObject _object(
  String label, {
  String id = 'NGC9999',
  CatalogType catalog = CatalogType.ngc,
}) => CatalogObject(
  id: id,
  number: int.parse(id.replaceAll(RegExp(r'\D'), '')),
  catalog: catalog,
  name: id,
  type: label,
  constellation: '-',
  ra: '-',
  dec: '-',
  magnitude: '-',
);

class _BrokenThumbnailBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => key.endsWith('m042.webp')
      ? Future.error(StateError('Test thumbnail decode/load failure'))
      : rootBundle.load(key);
}

void main() {
  test(
    'every canonical type has its own symbol and legacy labels are covered',
    () {
      final mapped = ObjectType.values
          .map((type) => CatalogSymbolKind.forObject(_object(type.label)))
          .toSet();
      expect(mapped.length, ObjectType.values.length);
      expect(
        CatalogSymbolKind.forObject(
          _object('혜성', id: 'solar_11', catalog: CatalogType.solar),
        ),
        CatalogSymbolKind.comet,
      );
      expect(
        CatalogSymbolKind.forObject(_object('성단과 성운')),
        CatalogSymbolKind.nebulaWithCluster,
      );
      expect(
        CatalogSymbolKind.forObject(
          _object('항성', id: 'solar_1', catalog: CatalogType.solar),
        ),
        CatalogSymbolKind.sun,
      );
    },
  );

  test(
    'all vector silhouettes paint visible and distinct pixels at two sizes',
    () async {
      for (final side in [20, 80]) {
        final signatures = <String>{};
        for (final kind in CatalogSymbolKind.values) {
          final recorder = ui.PictureRecorder();
          CatalogSymbolPainter(
            kind,
          ).paint(Canvas(recorder), Size.square(side.toDouble()));
          final picture = recorder.endRecording();
          final bitmap = await picture.toImage(side, side);
          final pixels = (await bitmap.toByteData())!.buffer.asUint8List();
          int count = 0;
          final silhouette = StringBuffer();
          for (var i = 3; i < pixels.length; i += 4) {
            final visible = pixels[i] > 100;
            silhouette.write(visible ? '1' : '0');
            if (visible) count++;
          }
          expect(count, greaterThan(7), reason: kind.name);
          expect(
            signatures.add(silhouette.toString()),
            isTrue,
            reason: kind.name,
          );
          bitmap.dispose();
          picture.dispose();
        }
      }
    },
  );

  testWidgets(
    'desktop and mobile card and catalog search use the same symbol',
    (tester) async {
      final object = _object('은하');
      var selected = false;
      for (final theme in [AppTheme.pcDark, AppTheme.mobileContentDark]) {
        selected = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox.square(
                    dimension: 180,
                    child: CatalogObjectCard(object: object, onTap: () {}),
                  ),
                  InlineCatalogSearchResults(
                    query: 'NGC9999',
                    allObjects: [object],
                    userPhotoFor: (_) => null,
                    onObjectSelected: (_) => selected = true,
                    debounceDuration: Duration.zero,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final symbols = tester.widgetList<CatalogObjectSymbol>(
          find.byType(CatalogObjectSymbol),
        );
        expect(
          symbols.map((symbol) => symbol.kind),
          everyElement(CatalogSymbolKind.galaxy),
        );
        expect(symbols.length, 2);
        await tester.tap(find.byType(ListTile));
        expect(selected, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'uses the symbol after a real image load error, not for a valid asset',
    (tester) async {
      final m42 = _object('발광성운', id: 'M42', catalog: CatalogType.messier);
      Future<void> show(
        CatalogObject object, {
        AssetBundle? bundle,
        String? userPhoto,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultAssetBundle(
                bundle: bundle ?? rootBundle,
                child: CatalogObjectImage(
                  key: ValueKey((object.id, bundle, userPhoto)),
                  object: object,
                  width: 80,
                  height: 80,
                  userPhotoPath: userPhoto,
                ),
              ),
            ),
          ),
        );
        // The engine completes file/asset decoding outside the fake clock.
        // Pump both queues without waiting on a listener tied to either zone.
        for (var attempt = 0; attempt < 100; attempt++) {
          if (find.byType(CatalogObjectSymbol).evaluate().isNotEmpty ||
              tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any((image) => image.image != null)) {
            return;
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        fail('Thumbnail did not display or fall back for ${object.id}');
      }

      await show(m42);
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.byType(CatalogObjectSymbol), findsNothing);

      await show(m42, bundle: _BrokenThumbnailBundle());
      expect(
        tester
            .widget<CatalogObjectSymbol>(find.byType(CatalogObjectSymbol))
            .kind,
        CatalogSymbolKind.emissionNebula,
      );

      await show(
        _object('은하'),
        userPhoto: 'missing-catalog-symbol-test-file.webp',
      );
      expect(
        tester
            .widget<CatalogObjectSymbol>(find.byType(CatalogObjectSymbol))
            .kind,
        CatalogSymbolKind.galaxy,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
