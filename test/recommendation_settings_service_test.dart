import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/services/recommendation_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy global azimuth values fall back to the full safe range',
    () async {
      SharedPreferences.setMockInitialValues({
        'rec_az_start_v1': 270,
        'rec_az_end_v1': 45,
      });

      final settings = await RecommendationSettingsService().load();

      expect(settings.azimuthStart, 0);
      expect(settings.azimuthEnd, 359);
    },
  );

  test(
    'saving user recommendation preferences keeps safe azimuth fallback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = RecommendationSettingsService();

      await service.save(
        RecommendationSettings(
          enabledCatalogs: {CatalogType.messier},
          azimuthStart: 120,
          azimuthEnd: 220,
          minAltitude: 25,
          maxAltitude: 80,
        ),
      );
      final settings = await service.load();

      expect(settings.enabledCatalogs, {CatalogType.messier});
      expect(settings.minAltitude, 0);
      expect(settings.maxAltitude, 90);
      expect(settings.azimuthStart, 0);
      expect(settings.azimuthEnd, 359);
    },
  );
}
