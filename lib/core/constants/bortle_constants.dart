/// Bortle light-pollution database constants.
///
/// Schema and metadata keys match [astronomy_data_builder] (Builder project).
class BortleConstants {
  BortleConstants._();

  static const String assetPath = 'assets/database/bortle.db';
  static const String databaseFileName = 'bortle.db';

  static const String tableMetadata = 'metadata';
  static const String tableBrightnessMap = 'brightness_map';

  static const List<String> metadataKeys = [
    'origin_x',
    'origin_y',
    'pixel_width',
    'pixel_height',
    'width',
    'height',
    'crs',
    'west',
    'south',
    'east',
    'north',
    'atlas_name',
    'atlas_version',
    'builder_version',
    'generated_at',
  ];

  static const Set<String> metadataFloatKeys = {
    'origin_x',
    'origin_y',
    'pixel_width',
    'pixel_height',
    'west',
    'south',
    'east',
    'north',
  };

  static const Set<String> metadataIntKeys = {'width', 'height'};
}
