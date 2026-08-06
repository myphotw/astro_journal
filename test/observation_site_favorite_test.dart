import 'package:astro_journal/core/constants/database_constants.dart';
import 'package:astro_journal/data/models/observation_site_favorite.dart';
import 'package:astro_journal/data/repositories/observation_site_favorite_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemoryObservationSiteFavoriteRepository
    implements ObservationSiteFavoriteRepository {
  final List<ObservationSiteFavorite> _items = [];

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((item) => item.id == id);
  }

  @override
  Future<List<ObservationSiteFavorite>> getAll() async {
    return List<ObservationSiteFavorite>.from(_items);
  }

  @override
  Future<ObservationSiteFavorite?> getById(String id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> save(ObservationSiteFavorite favorite) async {
    _items.removeWhere((item) => item.id == favorite.id);
    _items.add(favorite);
  }
}

void main() {
  group('ObservationSiteFavorite', () {
    test('toMap/fromMap roundtrip', () {
      final createdAt = DateTime(2026, 7, 7, 12, 30);
      final favorite = ObservationSiteFavorite(
        id: 'fav-1',
        name: '지리산 정령치',
        latitude: 35.336,
        longitude: 127.730,
        bortle: 2,
        sqm: 21.8,
        brightnessGrade: 'Bortle 2 · 탁월한 암야',
        createdAt: createdAt,
      );

      final restored = ObservationSiteFavorite.fromMap(favorite.toMap());

      expect(restored.id, favorite.id);
      expect(restored.name, favorite.name);
      expect(restored.latitude, favorite.latitude);
      expect(restored.longitude, favorite.longitude);
      expect(restored.bortle, favorite.bortle);
      expect(restored.sqm, favorite.sqm);
      expect(restored.brightnessGrade, favorite.brightnessGrade);
      expect(restored.createdAt, favorite.createdAt);
    });

    test('map uses database column names', () {
      final favorite = ObservationSiteFavorite(
        id: 'fav-1',
        name: '집',
        latitude: 37.5,
        longitude: 127.0,
        createdAt: DateTime(2026, 1, 1),
      );

      final map = favorite.toMap();

      expect(map[DatabaseConstants.colId], 'fav-1');
      expect(map[DatabaseConstants.colName], '집');
      expect(map[DatabaseConstants.colLatitude], 37.5);
      expect(map[DatabaseConstants.colLongitude], 127.0);
    });
  });

  group('ObservationSiteFavoriteRepository', () {
    late InMemoryObservationSiteFavoriteRepository repository;

    setUp(() {
      repository = InMemoryObservationSiteFavoriteRepository();
    });

    test('save and getAll', () async {
      final favorite = ObservationSiteFavorite(
        id: 'fav-1',
        name: '대부도',
        latitude: 37.2,
        longitude: 126.5,
        bortle: 4,
        createdAt: DateTime(2026, 7, 7),
      );

      await repository.save(favorite);
      final all = await repository.getAll();

      expect(all, hasLength(1));
      expect(all.first.name, '대부도');
    });

    test('delete removes favorite', () async {
      final favorite = ObservationSiteFavorite(
        id: 'fav-1',
        name: '집',
        latitude: 37.5,
        longitude: 127.0,
        createdAt: DateTime(2026, 7, 7),
      );

      await repository.save(favorite);
      await repository.delete('fav-1');

      expect(await repository.getAll(), isEmpty);
    });
  });
}
