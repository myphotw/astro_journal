import 'package:astro_journal/services/google_maps_native_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleMapsNativeKeyService', () {
    test('getStatus returns unconfigured on test VM (no native channel)', () async {
      final status = await GoogleMapsNativeKeyService.getStatus();
      expect(status.configured, isFalse);
      expect(status.keyLength, 0);
    });
  });
}
