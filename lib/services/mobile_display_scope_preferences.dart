import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MobileDisplayScreen { catalog, skyMap }

/// Local display preferences only; the famous object IDs still come from
/// CatalogFavoriteController.
class MobileDisplayScopePreferences {
  const MobileDisplayScopePreferences();

  String _key(MobileDisplayScreen screen) => switch (screen) {
    MobileDisplayScreen.catalog => 'mobile_catalog_famous_only',
    MobileDisplayScreen.skyMap => 'mobile_sky_map_famous_only',
  };

  Future<bool?> read(MobileDisplayScreen screen) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.get(_key(screen));
      return value is bool ? value : null;
    } catch (_) {
      debugPrint(
        'Could not read the mobile display preference for ${screen.name}.',
      );
      return null;
    }
  }

  Future<void> write(MobileDisplayScreen screen, bool famousOnly) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await prefs.setBool(_key(screen), famousOnly)) return;
    } catch (_) {
      // The user's in-session selection remains active if storage fails.
    }
    debugPrint(
      'Could not save the mobile display preference for ${screen.name}.',
    );
  }
}
