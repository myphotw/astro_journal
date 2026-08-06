import 'api_key_service.dart';
import 'google_maps_native_key_service.dart';

/// Decides whether native GoogleMap can be shown.
class GoogleMapsKeyReadiness {
  GoogleMapsKeyReadiness._();

  static Future<bool> isReady(ApiKeyService apiKeyService) async {
    await GoogleMapsNativeKeyService.syncKey(
      await apiKeyService.get(ApiKeyType.googleMaps),
      force: true,
    );

    if (await apiKeyService.has(ApiKeyType.googleMaps)) {
      return true;
    }

    final native = await GoogleMapsNativeKeyService.getStatus();
    return native.configured;
  }
}
