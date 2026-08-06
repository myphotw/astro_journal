import 'dart:convert';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/catalog_object_metadata_overrides.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/catalog_metadata_enricher.dart';
import 'package:astro_journal/services/equipment/angular_size_resolver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// SEDS / SIMBAD 등 일반 참고 메이저축(arcmin).
const _referenceMajorArcmin = <String, double>{
  'M1': 6,
  'M13': 20,
  'M31': 190,
  'M42': 85,
  'M57': 1.4,
  'M81': 27,
  'M82': 11,
  'M101': 28,
  'NGC 7000': 120,
  'NGC 2237': 80,
  'IC 1396': 170,
  'NGC 6960': 60,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catalog angular size audit (DB import pipeline)', () {
    late List<CatalogObject> enriched;

    setUpAll(() async {
      enriched = await _loadEnrichedCatalog();
    });

    test('Messier 110개 모두 정밀 angular_size 보유', () {
      final messier = enriched.where((o) => o.catalog == CatalogType.messier);
      expect(messier.length, 110);

      final withoutExact = messier
          .where(
            (o) =>
                o.angularSize == null || o.angularSize!.startsWith('약 '),
          )
          .map((o) => o.displayName)
          .toList();

      expect(withoutExact, isEmpty, reason: 'Missing exact size: $withoutExact');
    });

    test('유명 NGC/IC 오버라이드가 enrich 후 DB 값과 일치', () {
      for (final id in [
        'NGC 7000',
        'IC 1396',
        'NGC 2237',
        'NGC 6960',
        'NGC 6888',
      ]) {
        final override = CatalogObjectMetadataOverrides.forId(id);
        expect(override?.angularSize, isNotNull, reason: id);

        final object = enriched.firstWhere((o) => o.displayName == id);
        expect(object.angularSize, override!.angularSize);
      }
    });

    test('주요 대상 참고 크기와 ±15% 이내', () {
      final mismatches = <String>[];

      for (final entry in _referenceMajorArcmin.entries) {
        final object = enriched.firstWhere(
          (o) => o.displayName == entry.key,
          orElse: () => throw StateError('${entry.key} not found'),
        );
        final parsed = _parseFirstArcmin(object.angularSize!);
        expect(parsed, isNotNull);

        final diff = (parsed! - entry.value).abs() / entry.value;
        if (diff > 0.15) {
          mismatches.add('${entry.key}: $parsed vs ${entry.value}');
        }
      }

      expect(mismatches, isEmpty, reason: mismatches.join(', '));
    });

    test('NGC/IC 대부분은 추정 구간(약) 크기 — 정밀값 아님', () {
      final ngcIc = enriched.where(
        (o) =>
            o.catalog == CatalogType.ngc ||
            o.catalog == CatalogType.ic ||
            o.catalog == CatalogType.sh2,
      );

      final approximate = ngcIc.where((o) => o.angularSize?.startsWith('약 ') ?? false);
      final exact = ngcIc.where(
        (o) => o.angularSize != null && !o.angularSize!.startsWith('약 '),
      );

      expect(approximate.length, greaterThan(exact.length));
    });

    test('AngularSizeResolver는 타원 크기의 장축(첫 arcmin)만 사용', () {
      const resolver = AngularSizeResolver();
      final m82 = enriched.firstWhere((o) => o.displayName == 'M82');

      expect(m82.angularSize, "11' × 4'");
      final degrees = resolver.resolveDegrees(m82);
      expect(degrees, closeTo(11 / 60, 0.001));
    });

    test('추정 구간 문자열은 하한값으로 파싱됨', () {
      const resolver = AngularSizeResolver();
      final sample = enriched.firstWhere(
        (o) => o.angularSize?.startsWith("약 15'~30'") ?? false,
        orElse: () => enriched.firstWhere(
          (o) => o.angularSize?.startsWith('약 ') ?? false,
        ),
      );

      final degrees = resolver.resolveDegrees(sample);
      expect(degrees, greaterThan(0));
      expect(degrees, lessThanOrEqualTo(0.5));
    });
  });
}

double? _parseFirstArcmin(String raw) {
  final match = RegExp(r"(\d+(?:\.\d+)?)\s*'").firstMatch(raw);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

Future<List<CatalogObject>> _loadEnrichedCatalog() async {
  const enricher = CatalogMetadataEnricher();
  final messier = await _loadList('assets/catalog/messier.json', CatalogType.messier);
  final seestar = await _loadSeestar('assets/catalog/seestar_catalog.json');
  final solar = await _loadList('assets/catalog/solar.json', CatalogType.solar);
  final milky = await _loadList('assets/catalog/milkyway.json', CatalogType.milky);

  return [...messier, ...seestar, ...solar, ...milky].map(enricher.enrich).toList();
}

Future<List<CatalogObject>> _loadList(String path, CatalogType catalog) async {
  final jsonString = await rootBundle.loadString(path);
  final jsonList = jsonDecode(jsonString) as List<dynamic>;
  return jsonList
      .map((item) => CatalogObject.fromJson(item as Map<String, dynamic>, catalog))
      .toList();
}

Future<List<CatalogObject>> _loadSeestar(String path) async {
  final jsonString = await rootBundle.loadString(path);
  final jsonList = jsonDecode(jsonString) as List<dynamic>;
  return jsonList.map((item) {
    final map = item as Map<String, dynamic>;
    return CatalogObject.fromJson(
      map,
      CatalogType.fromValue(map['catalog'] as String),
    );
  }).toList();
}
