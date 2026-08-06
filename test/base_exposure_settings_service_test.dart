import 'package:astro_journal/services/base_exposure_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseExposureSettingsService', () {
    late BaseExposureSettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = BaseExposureSettingsService();
    });

    test('load returns default reference bortle 8', () async {
      final settings = await service.load();
      expect(settings.referenceBortle, 8);
    });

    test('save and load persists reference bortle', () async {
      await service.save(const BaseExposureSettings(referenceBortle: 5));
      final settings = await service.load();
      expect(settings.referenceBortle, 5);
    });

    test('save clamps reference bortle to 1-9', () async {
      await service.save(const BaseExposureSettings(referenceBortle: 0));
      expect((await service.load()).referenceBortle, 1);

      await service.save(const BaseExposureSettings(referenceBortle: 12));
      expect((await service.load()).referenceBortle, 9);
    });
  });
}
