import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/datasources/catalog_favorite_cache_data_source.dart';
import 'package:astro_journal/data/datasources/gallery_cache_local_datasource.dart';
import 'package:astro_journal/data/models/catalog_candidate.dart';
import 'package:astro_journal/data/models/catalog_favorite.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/services/catalog_favorite_controller.dart';
import 'package:astro_journal/services/tc_backend_catalog_favorite_service.dart';
import 'package:astro_journal/shared/widgets/catalog_favorite_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('local cache round-trips the last synchronized server list', () async {
    final galleryCache = _GalleryCache();
    final cache = CatalogFavoriteCacheLocalDataSource(galleryCache);

    await cache.write([_favorite('NGC2237'), _favorite('solar_6')]);

    expect((await cache.read()).map((favorite) => favorite.catalogObjectId), [
      'NGC2237',
      'solar_6',
    ]);
  });

  test('offline initialization keeps the last synchronized cache', () async {
    final cache = _Cache([_favorite('solar_6')]);
    final controller = CatalogFavoriteController(
      remoteApi: _Remote(failList: true),
      cache: cache,
      catalogRepository: _CatalogRepository([_jupiter]),
    );

    await controller.initialize();

    expect(controller.isFavorite('solar_6'), isTrue);
    expect(controller.favoriteObjects.single.id, 'solar_6');
    expect(controller.lastSyncError, isNotNull);
  });

  test(
    'successful add and remove update the cache only after the server',
    () async {
      final remote = _Remote();
      final cache = _Cache([]);
      final controller = CatalogFavoriteController(
        remoteApi: remote,
        cache: cache,
        catalogRepository: _CatalogRepository([_jupiter]),
      );

      await controller.toggle('solar_6');
      expect(controller.isFavorite('solar_6'), isTrue);
      expect(cache.values.single.catalogObjectId, 'solar_6');

      await controller.toggle('solar_6');
      expect(controller.isFavorite('solar_6'), isFalse);
      expect(cache.values, isEmpty);
    },
  );

  test('two clients restore the same server-authoritative list', () async {
    final remote = _Remote();
    final repository = _CatalogRepository([_jupiter]);
    final windows = CatalogFavoriteController(
      remoteApi: remote,
      cache: _Cache([]),
      catalogRepository: repository,
    );
    final android = CatalogFavoriteController(
      remoteApi: remote,
      cache: _Cache([]),
      catalogRepository: repository,
    );

    await windows.toggle('solar_6');
    await android.initialize();

    expect(windows.isFavorite('solar_6'), isTrue);
    expect(android.isFavorite('solar_6'), isTrue);
  });

  test('failed mutation preserves the previous state', () async {
    final controller = CatalogFavoriteController(
      remoteApi: _Remote(failList: true, failMutations: true),
      cache: _Cache([_favorite('solar_6')]),
      catalogRepository: _CatalogRepository([_jupiter]),
    );
    await controller.initialize();

    await expectLater(
      controller.toggle('solar_6'),
      throwsA(isA<CatalogFavoriteActionException>()),
    );
    expect(controller.isFavorite('solar_6'), isTrue);
  });

  test('unknown catalog ID is rejected before the server request', () async {
    final remote = _Remote();
    final controller = CatalogFavoriteController(
      remoteApi: remote,
      cache: _Cache([]),
      catalogRepository: const _CatalogRepository([]),
    );

    await expectLater(
      controller.toggle('missing-object'),
      throwsA(isA<CatalogFavoriteActionException>()),
    );
    expect(remote.mutationCalls, 0);
  });

  testWidgets('two detail entry points share one favorite state', (
    tester,
  ) async {
    final controller = CatalogFavoriteController(
      remoteApi: _Remote(),
      cache: _Cache([]),
      catalogRepository: _CatalogRepository([_jupiter]),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                CatalogFavoriteButton(catalogObjectId: 'solar_6'),
                CatalogFavoriteButton(catalogObjectId: 'solar_6'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('catalog-favorite-solar_6')).first,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
  });
}

CatalogFavorite _favorite(String id) => CatalogFavorite(
  catalogObjectId: id,
  createdAt: DateTime.utc(2026, 10, 21),
  updatedAt: DateTime.utc(2026, 10, 21),
);

const _jupiter = CatalogObject(
  id: 'solar_6',
  number: 6,
  catalog: CatalogType.solar,
  name: '목성',
  type: '행성',
  constellation: '-',
  ra: '-',
  dec: '-',
  magnitude: '-2.9',
);

class _Cache implements CatalogFavoriteCacheDataSource {
  _Cache(this.values);

  List<CatalogFavorite> values;

  @override
  Future<List<CatalogFavorite>> read() async => List.of(values);

  @override
  Future<void> write(List<CatalogFavorite> favorites) async {
    values = List.of(favorites);
  }
}

class _GalleryCache implements GalleryCacheDataSource {
  GalleryCacheEntry? entry;

  @override
  Future<GalleryCacheEntry?> read(String key) async =>
      entry?.key == key ? entry : null;

  @override
  Future<void> write(GalleryCacheEntry value) async {
    entry = value;
  }
}

class _Remote implements CatalogFavoriteRemoteApi {
  _Remote({this.failList = false, this.failMutations = false});

  final bool failList;
  final bool failMutations;
  final Map<String, CatalogFavorite> values = {};
  int mutationCalls = 0;

  @override
  Future<List<CatalogFavorite>> list() async {
    if (failList) throw _offline;
    return values.values.toList(growable: false);
  }

  @override
  Future<CatalogFavorite> add(String catalogObjectId) async {
    mutationCalls += 1;
    if (failMutations) throw _offline;
    return values.putIfAbsent(
      catalogObjectId,
      () => _favorite(catalogObjectId),
    );
  }

  @override
  Future<CatalogFavoriteDeleteResult> remove(String catalogObjectId) async {
    mutationCalls += 1;
    if (failMutations) throw _offline;
    return CatalogFavoriteDeleteResult(
      catalogObjectId: catalogObjectId,
      deleted: values.remove(catalogObjectId) != null,
    );
  }

  static const _offline = CatalogFavoriteRemoteException(
    type: CatalogFavoriteRemoteErrorType.network,
    message: 'offline',
  );
}

class _CatalogRepository implements CatalogRepository {
  const _CatalogRepository(this.objects);

  final List<CatalogObject> objects;

  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => objects;
  @override
  Future<CatalogObject?> getById(String id) async {
    for (final object in objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  @override
  Future<List<CatalogObject>> getByCatalog(CatalogType type) async => const [];
  @override
  Future<List<CatalogObject>> search(String query, {int limit = 50}) async =>
      const [];
  @override
  Future<void> updateCaptured(
    String id, {
    required bool captured,
    String? capturedDate,
  }) async {}
  @override
  Future<void> insert(CatalogObject object) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<CatalogCandidate>> findNearbyObjects({
    required double raDeg,
    required double decDeg,
    required double radiusDeg,
  }) async => const [];
  @override
  Future<List<CatalogObject>> findObjectsInPhotoField({
    required double centerRaDeg,
    required double centerDecDeg,
    required double fovWidthDeg,
    required double fovHeightDeg,
    required double rotationDeg,
  }) async => const [];
}
