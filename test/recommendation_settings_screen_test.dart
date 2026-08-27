import 'package:astro_journal/features/settings/view/recommendation_settings_screen.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every persisted recommendation catalog is user-selectable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      Provider<RecommendationSettingsService>(
        create: (_) => RecommendationSettingsService(),
        child: const MaterialApp(home: RecommendationSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Barnard'), findsOneWidget);
    expect(find.text('LDN'), findsOneWidget);
    expect(find.text('LBN'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(11));
  });
}
