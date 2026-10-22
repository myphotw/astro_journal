import 'dart:io';

import 'package:astro_journal/features/light_pollution_map/view/light_pollution_map_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final application = File(
    'android/app/src/main/kotlin/com/example/astro_journal/MainApplication.kt',
  ).readAsStringSync();
  final activity = File(
    'android/app/src/main/kotlin/com/example/astro_journal/MainActivity.kt',
  ).readAsStringSync();
  final screen = File(
    'lib/features/light_pollution_map/view/light_pollution_map_screen.dart',
  ).readAsStringSync();
  final windowsScreen = File(
    'lib/features/light_pollution_map/view/windows_light_pollution_map_screen.dart',
  ).readAsStringSync();
  final viewModel = File(
    'lib/features/light_pollution_map/viewmodel/light_pollution_map_view_model.dart',
  ).readAsStringSync();
  final favoritesDropdown = File(
    'lib/features/light_pollution_map/widgets/light_pollution_favorites_dropdown.dart',
  ).readAsStringSync();
  final debugManifest = File(
    'android/app/src/debug/AndroidManifest.xml',
  ).readAsStringSync();

  test('Android Maps manifest contract is complete', () {
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:hardwareAccelerated="true"'));
    expect(manifest, contains('com.google.android.geo.API_KEY'));
    expect(manifest, contains('@string/google_maps_api_key'));
    expect(gradle, contains('applicationId = "com.example.astro_journal"'));
    expect(
      gradle,
      contains('resValue("string", "google_maps_api_key", googleMapsApiKey)'),
    );
  });

  test('Maps initialization follows the Android Application lifecycle', () {
    final superOnCreate = application.indexOf('super.onCreate()');
    final mapsInitialize = application.indexOf('MapsInitializer.initialize');
    expect(superOnCreate, greaterThanOrEqualTo(0));
    expect(mapsInitialize, greaterThan(superOnCreate));
    expect(application, contains('MapsInitializer.Renderer.LATEST'));
    expect(application, contains('Maps renderer=\$renderer'));
    expect(application, isNot(contains('GoogleMapsDiagnosticsStore')));

    final activitySuper = activity.indexOf(
      'super.onCreate(savedInstanceState)',
    );
    final activityKey = activity.indexOf(
      'GoogleMapsApiKeyHolder.applyBuildConfiguredKey(applicationContext)',
    );
    expect(activitySuper, greaterThanOrEqualTo(0));
    expect(activityKey, greaterThan(activitySuper));
  });

  test('temporary Maps diagnostics and native test are removed', () {
    expect(debugManifest, isNot(contains('.NativeMapTestActivity')));
    expect(manifest, isNot(contains('.NativeMapTestActivity')));
    expect(activity, isNot(contains('"getMapsDiagnostics"')));
    expect(activity, isNot(contains('"openNativeMapTest"')));
    expect(screen, isNot(contains('MapsDebugDiagnosticsPanel')));
    expect(screen, isNot(contains('MAP_BASEMAP_UNVERIFIED')));
  });

  test('basemap fills the canvas and Bortle tiles stay optional', () {
    expect(const LightPollutionMapScreen(isActive: false).isActive, isFalse);
    final googleMap = screen.indexOf('child: GoogleMap(');
    final positionedFill = screen.lastIndexOf('Positioned.fill(', googleMap);
    expect(googleMap, greaterThanOrEqualTo(0));
    expect(positionedFill, greaterThanOrEqualTo(0));
    expect(screen, contains('mapType: MapType.normal'));
    expect(screen, contains('target: vm.mapCenter'));
    expect(screen, contains('widget.isActive && _showTileOverlay'));
    expect(screen, contains('? vm.tileOverlays'));
    expect(screen, contains(': const {}'));
    expect(screen, contains('onMapCreated: _onMapCreated'));
  });

  test('saved-site dropdown has no weather or recommendation pipeline', () {
    expect(viewModel, isNot(contains('_loadFavoriteSummaries')));
    expect(viewModel, isNot(contains('_buildFavoriteSummary')));
    expect(viewModel, isNot(contains('RecommendationEngine')));
    expect(viewModel, isNot(contains('CatalogRepository')));
    expect(viewModel, isNot(contains('EquipmentRepository')));
    expect(favoritesDropdown, contains('viewModel.favorites'));
    expect(favoritesDropdown, contains('favorite.bortle'));
    expect(favoritesDropdown, isNot(contains('추천장비')));
    expect(favoritesDropdown, isNot(contains('추천대상')));
  });

  test('mobile and Windows show selected or current location, not both', () {
    for (final source in [screen, windowsScreen]) {
      expect(source, contains('if (vm.hasSelection)'));
      expect(source, isNot(contains('if (vm.hasSelection) ...[')));
      expect(
        RegExp('LightPollutionLocationCard\\(').allMatches(source).length,
        2,
      );
      final clearSelection = source.indexOf('vm.clearSelection();');
      final refreshCurrent = source.indexOf(
        'await vm.refreshCurrentLocation();',
      );
      expect(clearSelection, greaterThanOrEqualTo(0));
      expect(refreshCurrent, greaterThan(clearSelection));
    }
  });
}
