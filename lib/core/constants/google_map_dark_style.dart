/// Dark map style aligned with [AppColors] background tones.
class GoogleMapDarkStyle {
  GoogleMapDarkStyle._();

  static const String json = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#080B14"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#94A3B8"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#080B14"}]},
  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#0D1B3E"}]},
  {"featureType": "landscape", "elementType": "geometry", "stylers": [{"color": "#0D1B3E"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#111827"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#0F172A"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#1E293B"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#334155"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#334155"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#111827"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#020617"}]}
]
''';
}
