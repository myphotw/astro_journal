import 'package:astro_journal/features/light_pollution_map/widgets/light_pollution_favorite_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('favorite dialog owns its controller through route disposal', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const LightPollutionFavoriteNameDialog(
                    defaultName: '현재 위치',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('light-map-favorite-name')),
      '회사 관측지',
    );
    await tester.tap(find.byKey(const Key('light-map-save-favorite')));
    await tester.pumpAndSettle();

    expect(result, '회사 관측지');
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing the route while the dialog is open disposes safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => const LightPollutionFavoriteNameDialog(
                  defaultName: '현재 위치',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
