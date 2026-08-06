/// Constants for light-pollution [TileOverlay] generation.
class LightPollutionTileConstants {
  LightPollutionTileConstants._();

  static const int tileSize = 256;

  /// Default overlay opacity (0.0–1.0). UI slider will adjust this later.
  static const double defaultOverlayOpacity = 0.42;

  /// Current overlay opacity. Separated for future user slider (0%–100%).
  static double overlayOpacity = defaultOverlayOpacity;

  /// Atlas bilinear 샘플 간격. 샘플 사이 픽셀은 화면 공간 bilinear.
  static int samplingStrideForZoom(int zoom) {
    if (zoom <= 7) return 8;
    if (zoom <= 10) return 6;
    if (zoom <= 13) return 4;
    return 2;
  }
}
