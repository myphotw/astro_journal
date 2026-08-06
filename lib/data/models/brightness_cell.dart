/// A single brightness_map pixel from bortle.db.
class BrightnessCell {
  const BrightnessCell({
    required this.row,
    required this.col,
    required this.brightness,
  });

  final int row;
  final int col;
  final double brightness;
}
