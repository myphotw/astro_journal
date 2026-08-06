import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GoogleMapsNativeKeyService {
  GoogleMapsNativeKeyService._();

  static const _channel = MethodChannel('com.example.astro_journal/maps');
  static String? _lastSyncedKey;

  static Future<void> syncKey(String? apiKey, {bool force = false}) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final trimmed = apiKey?.trim() ?? '';
    if (!force && trimmed == (_lastSyncedKey ?? '')) return;

    try {
      await _channel.invokeMethod<void>('syncGoogleMapsApiKey', {
        'apiKey': trimmed,
      });
      _lastSyncedKey = trimmed.isEmpty ? null : trimmed;
    } catch (error, stack) {
      debugPrint('GoogleMapsNativeKeyService.syncKey failed: $error\n$stack');
    }
  }

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

  static Future<String?> getManifestApiKey() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      return await _channel.invokeMethod<String>('getManifestMapsApiKey');
    } catch (_) {
      return null;
    }
  }
}
