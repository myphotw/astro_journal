import 'google_maps_native_key_service.dart';

/// Decides whether native GoogleMap can be shown.
class GoogleMapsKeyReadiness {
  GoogleMapsKeyReadiness._();

  static Future<bool> isReady() async {
    final native = await GoogleMapsNativeKeyService.getStatus();
    return native.configured;
  }
}
