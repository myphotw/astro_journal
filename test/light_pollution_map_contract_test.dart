import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final application = File(
    'android/app/src/main/kotlin/com/example/astro_journal/MainApplication.kt',
  ).readAsStringSync();
  final screen = File(
    'lib/features/light_pollution_map/view/light_pollution_map_screen.dart',
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
  });

  test('basemap fills the canvas and Bortle tiles stay optional', () {
    final googleMap = screen.indexOf('child: GoogleMap(');
    final positionedFill = screen.lastIndexOf('Positioned.fill(', googleMap);
    expect(googleMap, greaterThanOrEqualTo(0));
    expect(positionedFill, greaterThanOrEqualTo(0));
    expect(screen, contains('mapType: MapType.normal'));
    expect(screen, contains('target: vm.mapCenter'));
    expect(screen, contains('widget.isActive && _showTileOverlay'));
    expect(screen, contains('? vm.tileOverlays'));
    expect(screen, contains(': const {}'));
  });
}
