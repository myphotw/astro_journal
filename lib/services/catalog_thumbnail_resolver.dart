import '../data/models/catalog_object.dart';
import '../data/models/shooting_record.dart';
import 'catalog_search_service.dart';

enum CatalogThumbnailSource { userPhoto, asset, fallback }

class CatalogThumbnailSelection {
  const CatalogThumbnailSelection._(this.source, this.path);

  const CatalogThumbnailSelection.userPhoto(String path)
    : this._(CatalogThumbnailSource.userPhoto, path);

  const CatalogThumbnailSelection.asset(String path)
    : this._(CatalogThumbnailSource.asset, path);

  const CatalogThumbnailSelection.fallback()
    : this._(CatalogThumbnailSource.fallback, null);

  final CatalogThumbnailSource source;
  final String? path;

  bool get hasImage => source != CatalogThumbnailSource.fallback;
}

/// Resolves bundled catalog thumbnails and the user's preferred capture.
///
/// Bundled assets are keyed only by canonical catalog identity. They are never
/// persisted in [ShootingRecord] or mixed into the user's Gallery records.
abstract final class CatalogThumbnailResolver {
  static const String assetDirectory = 'assets/catalog/thumbnails';

  /// The non-Messier portion of the reviewed 194-image inventory.
  /// Messier M1-M110 are complete and are handled as a validated range.
  static const Set<String> _supportedNonMessierIds = {
    'C14',
    'IC1396',
    'IC1805',
    'IC1848',
    'IC2118',
    'IC2177',
    'IC2944',
    'IC342',
    'IC405',
    'IC410',
    'IC434',
    'IC443',
    'IC4592',
    'IC4604',
    'IC4628',
    'IC5070',
    'IC5146',
    'NGC104',
    'NGC1316',
    'NGC1365',
    'NGC1499',
    'NGC1975',
    'NGC2024',
    'NGC2175',
    'NGC2237',
    'NGC2244',
    'NGC2261',
    'NGC2359',
    'NGC2392',
    'NGC2403',
    'NGC246',
    'NGC2467',
    'NGC247',
    'NGC253',
    'NGC2736',
    'NGC281',
    'NGC2903',
    'NGC292',
    'NGC300',
    'NGC3132',
    'NGC3199',
    'NGC3242',
    'NGC3372',
    'NGC3532',
    'NGC3576',
    'NGC3628',
    'NGC4038',
    'NGC4244',
    'NGC4565',
    'NGC457',
    'NGC4631',
    'NGC4755',
    'NGC4945',
    'NGC5128',
    'NGC5139',
    'NGC55',
    'NGC5907',
    'NGC6188',
    'NGC6231',
    'NGC6302',
    'NGC6334',
    'NGC6357',
    'NGC6543',
    'NGC6744',
    'NGC6826',
    'NGC6888',
    'NGC6946',
    'NGC6960',
    'NGC6992',
    'NGC6995',
    'NGC7000',
    'NGC7009',
    'NGC7023',
    'NGC7293',
    'NGC7331',
    'NGC7380',
    'NGC752',
    'NGC7538',
    'NGC7635',
    'NGC7662',
    'NGC7822',
    'NGC891',
    'SH2-240',
    'SH2-276',
  };

  static String normalizeCanonicalId(String id) =>
      id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static String? thumbnailAssetFor(CatalogObject object) =>
      thumbnailAssetForId(object.effectivePrimaryId);

  static String? thumbnailAssetForId(String effectivePrimaryId) {
    final id = normalizeCanonicalId(effectivePrimaryId);
    final messier = RegExp(r'^M(\d{1,3})$').firstMatch(id);
    if (messier != null) {
      final number = int.parse(messier.group(1)!);
      if (number < 1 || number > 110) return null;
      return '$assetDirectory/m${number.toString().padLeft(3, '0')}.webp';
    }

    if (!_supportedNonMessierIds.contains(id)) return null;

    final caldwell = RegExp(r'^C(\d+)$').firstMatch(id);
    if (caldwell != null) {
      final number = int.parse(caldwell.group(1)!);
      return '$assetDirectory/c${number.toString().padLeft(3, '0')}.webp';
    }
    return '$assetDirectory/${id.toLowerCase()}.webp';
  }

  static CatalogThumbnailSelection resolve(
    CatalogObject object, {
    String? userPhotoPath,
  }) {
    final normalizedPhotoPath = userPhotoPath?.trim();
    if (normalizedPhotoPath != null && normalizedPhotoPath.isNotEmpty) {
      return CatalogThumbnailSelection.userPhoto(normalizedPhotoPath);
    }
    final asset = thumbnailAssetFor(object);
    return asset == null
        ? const CatalogThumbnailSelection.fallback()
        : CatalogThumbnailSelection.asset(asset);
  }

  /// Builds one shared representative-photo index for Catalog and Home.
  /// A marked representative wins; otherwise the newest photo is used.
  static Map<String, String> buildUserPhotoIndex({
    required List<ShootingRecord> records,
    required List<CatalogObject> catalog,
  }) {
    final exactByLowerId = {
      for (final object in catalog) object.id.toLowerCase(): object,
    };
    final searchService = CatalogSearchService();
    final sorted = [...records]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final result = <String, String>{};

    String canonicalIdFor(String identity) {
      final trimmed = identity.trim();
      final exact = exactByLowerId[trimmed.toLowerCase()];
      final resolved = exact == null
          ? searchService.resolveTarget(trimmed, catalog)
          : CatalogSearchService.resolvePrimaryFromList(exact, catalog);
      return normalizeCanonicalId(resolved?.effectivePrimaryId ?? trimmed);
    }

    void add(Iterable<ShootingRecord> candidates) {
      for (final record in candidates) {
        final path = record.photoUri?.trim();
        if (path == null || path.isEmpty) continue;
        result.putIfAbsent(
          canonicalIdFor(record.celestialObjectId),
          () => path,
        );
      }
    }

    add(sorted.where((record) => record.isRepresentative));
    add(sorted);
    return result;
  }

  static String? userPhotoFor(
    CatalogObject object,
    Map<String, String> userPhotoIndex,
  ) => userPhotoIndex[normalizeCanonicalId(object.effectivePrimaryId)];
}
