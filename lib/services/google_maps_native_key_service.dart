import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoogleMapsNativeKeyService {
  GoogleMapsNativeKeyService._();

  static const _channel = MethodChannel('com.example.astro_journal/maps');

  static Future<({bool configured, int keyLength})> getStatus() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return (configured: false, keyLength: 0);
    }

    try {
      final status = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getMapsApiKeyStatus',
      );
      return (
        configured: status?['configured'] == true,
        keyLength: (status?['keyLength'] as int?) ?? 0,
      );
    } catch (_) {
      return (configured: false, keyLength: 0);
    }
  }
}
