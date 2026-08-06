/// GPS lookup result including grid coordinates and brightness value.
class BortleLookupResult {
  const BortleLookupResult({
    required this.latitude,
    required this.longitude,
    required this.row,
    required this.col,
    required this.brightness,
  });

  final double latitude;
  final double longitude;
  final int row;
  final int col;
  final double brightness;
}
