import '../../core/constants/bortle_constants.dart';

/// Grid metadata from bortle.db (Builder [GridMetadata] equivalent).
class BortleMetadata {
  const BortleMetadata({
    required this.originX,
    required this.originY,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.width,
    required this.height,
    required this.crs,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.atlasName,
    required this.atlasVersion,
    required this.builderVersion,
    required this.generatedAt,
  });

  factory BortleMetadata.fromKeyValueRows(Map<String, String> rows) {
    final missing = BortleConstants.metadataKeys
        .where((key) => !rows.containsKey(key))
        .toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        'Missing metadata keys: ${missing.join(', ')}',
      );
    }

    double parseFloat(String key) => double.parse(rows[key]!);
    int parseInt(String key) => int.parse(rows[key]!);

    return BortleMetadata(
      originX: parseFloat('origin_x'),
      originY: parseFloat('origin_y'),
      pixelWidth: parseFloat('pixel_width'),
      pixelHeight: parseFloat('pixel_height'),
      width: parseInt('width'),
      height: parseInt('height'),
      crs: rows['crs']!,
      west: parseFloat('west'),
      south: parseFloat('south'),
      east: parseFloat('east'),
      north: parseFloat('north'),
      atlasName: rows['atlas_name']!,
      atlasVersion: rows['atlas_version']!,
      builderVersion: rows['builder_version']!,
      generatedAt: rows['generated_at']!,
    );
  }

  final double originX;
  final double originY;
  final double pixelWidth;
  final double pixelHeight;
  final int width;
  final int height;
  final String crs;
  final double west;
  final double south;
  final double east;
  final double north;
  final String atlasName;
  final String atlasVersion;
  final String builderVersion;
  final String generatedAt;

  /// WGS84 latitude/longitude → raster row/col (same as Builder / rasterio.index).
  ({int row, int col}) latLonToRowCol(double latitude, double longitude) {
    final col = ((longitude - originX) / pixelWidth).floor();
    final row = ((originY - latitude) / pixelHeight).floor();
    return (row: row, col: col);
  }

  bool isInBounds(int row, int col) {
    return row >= 0 && row < height && col >= 0 && col < width;
  }

  /// Converts WGS84 bounds to raster row/col ranges (Builder inverse of [latLonToRowCol]).
  ({int rowMin, int rowMax, int colMin, int colMax})? gpsBoundsToRowColBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    if (north <= south || east <= west) return null;

    var rowMin = ((originY - north) / pixelHeight).floor();
    var rowMax = ((originY - south) / pixelHeight).floor();
    var colMin = ((west - originX) / pixelWidth).floor();
    var colMax = ((east - originX) / pixelWidth).floor();

    rowMin = rowMin.clamp(0, height - 1);
    rowMax = rowMax.clamp(0, height - 1);
    colMin = colMin.clamp(0, width - 1);
    colMax = colMax.clamp(0, width - 1);

    if (rowMin > rowMax || colMin > colMax) return null;
    return (rowMin: rowMin, rowMax: rowMax, colMin: colMin, colMax: colMax);
  }

  /// Pixel edges in WGS84 (rasterio cell bounds).
  double pixelWest(int col) => originX + col * pixelWidth;

  double pixelEast(int col) => originX + (col + 1) * pixelWidth;

  double pixelNorth(int row) => originY - row * pixelHeight;

  double pixelSouth(int row) => originY - (row + 1) * pixelHeight;

  @override
  String toString() {
    return 'BortleMetadata('
        'originX: $originX, originY: $originY, '
        'pixelWidth: $pixelWidth, pixelHeight: $pixelHeight, '
        'width: $width, height: $height, crs: $crs, '
        'bounds: [$west,$south,$east,$north], '
        'atlas: $atlasName v$atlasVersion, '
        'builder: $builderVersion, generatedAt: $generatedAt)';
  }
}
