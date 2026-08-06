import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/eyepiece.dart';
import 'package:astro_journal/data/models/recommendation_result.dart';
import 'package:astro_journal/features/home/viewmodel/home_view_model.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = EquipmentRecommendationService();

  CatalogObject object({
    required String id,
    String type = '구상성단',
    String? angularSize,
  }) {
    return CatalogObject(
      id: id,
      number: 13,
      catalog: CatalogType.messier,
      name: id.toUpperCase(),
      type: type,
      constellation: 'Hercules',
      ra: '16h41m',
      dec: "+36°28'",
      magnitude: '5.8',
      angularSize: angularSize,
    );
  }

  Equipment seestarS30() {
    return const Equipment(
      id: 's30',
      name: 'Seestar S30 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 160,
      fovWidthDegrees: 2.24,
      fovHeightDegrees: 3.99,
    );
  }

  Equipment seestarS50() {
    return const Equipment(
      id: 's50',
      name: 'Seestar S50 Pro',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      focalLengthMm: 250,
      fovWidthDegrees: 0.72,
      fovHeightDegrees: 1.28,
    );
  }

  Equipment bcto90() {
    return Equipment(
      id: 'bcto',
      name: 'BCTO90',
      kind: EquipmentKind.reflector,
      purpose: EquipmentPurpose.visual,
      apertureMm: 90,
      focalLengthMm: 500,
      eyepieces: const [
        Eyepiece(
          id: 'ep25',
          equipmentId: 'bcto',
          name: '25mm',
          focalLengthMm: 25,
          afovDegrees: 50,
        ),
        Eyepiece(
          id: 'ep6',
          equipmentId: 'bcto',
          name: '6mm',
          focalLengthMm: 6,
          afovDegrees: 52,
        ),
      ],
    );
  }

  group('EquipmentRecommendationService', () {
    test('ranks imaging equipment by fit and excludes 확대 촬영 추천', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [seestarS50(), seestarS30()],
      );

      expect(result.imaging.length, 2);
      expect(result.imaging.first.score, greaterThanOrEqualTo(result.imaging.last.score));
      for (final item in result.imaging) {
        expect(item.reason, isNot('확대 촬영 추천'));
      }
    });

    test('uses 프레임 적합 or 촬영 가능 for small targets', () {
      final result = service.recommendForObject(
        object: object(id: 'm57', type: '행성상성운'),
        equipment: [seestarS30(), seestarS50()],
      );

      expect(
        result.imaging.any(
          (item) =>
              item.reason == '프레임 적합' || item.reason == '촬영 가능',
        ),
        isTrue,
      );
    });

    test('selects best eyepiece for M13 visual', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      final best = result.visual.first;
      expect(best.isRecommended, isTrue);
      expect(best.eyepiece, isNotNull);
      expect(best.eyepieceFocalLabel, isNotEmpty);
      expect(best.equipment.name, 'BCTO90');
      expect(best.screenFillPercent, greaterThan(0));
    });

    test('includes screen fill percent for imaging equipment', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [seestarS30(), seestarS50()],
      );

      expect(result.imaging, isNotEmpty);
      for (final item in result.imaging) {
        expect(item.screenFillPercent, greaterThan(0));
      }
    });

    test('ranks visual eyepiece combos excluding over 100% fill', () {
      final result = service.recommendForObject(
        object: object(id: 'm13'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      for (final item in result.visual) {
        expect(item.screenFillPercent, lessThanOrEqualTo(100));
        expect(item.isRecommended, isTrue);
      }
    });

    test('M31 on S30 Pro fits in one frame with orientation-aware fill', () {
      final result = service.recommendForObject(
        object: object(
          id: 'm31',
          type: '은하',
          angularSize: "190' × 60'",
        ),
        equipment: [seestarS30()],
      );

      expect(result.imaging, isNotEmpty);
      final s30 = result.imaging.firstWhere((e) => e.equipment.id == 's30');
      expect(s30.screenFillPercent, lessThan(100));
      expect(s30.screenFillNote, isNull);
      expect(s30.reason, isNot('모자이크 권장'));
    });

    test('excludes narrow eyepiece when target fills over 100% of FOV', () {
      final result = service.recommendForObject(
        object: object(
          id: 'm31',
          type: '은하',
          angularSize: "190' × 60'",
        ),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(
        result.visual.every((item) => item.screenFillPercent <= 100),
        isTrue,
      );
      expect(
        result.visual.any((item) => item.eyepiece?.focalLengthMm == 6),
        isFalse,
      );
    });

    test('downrates veil nebula for visual without eyepiece', () {
      final result = service.recommendForObject(
        object: object(id: 'ngc6960', type: '초신성잔해'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(result.visual.first.isRecommended, isFalse);
      expect(result.visual.first.eyepiece, isNull);
    });

    test('downrates NGC6334 for visual on 90mm', () {
      final result = service.recommendForObject(
        object: object(id: 'ngc6334', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(result.visual.first.isRecommended, isFalse);
      expect(result.visual.first.eyepiece, isNull);
    });

    test('recommends M8 visual without no-filter block', () {
      final result = service.recommendForObject(
        object: object(id: 'm8', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      expect(result.visual.first.isRecommended, isTrue);
      expect(result.visual.first.eyepiece, isNotNull);
    });

    test('NGC2237 visual uses central cluster recommendation', () {
      final result = service.recommendForObject(
        object: object(id: 'ngc2237', type: '발광성운'),
        equipment: [bcto90()],
      );

      expect(result.visual, isNotEmpty);
      final best = result.visual.first;
      expect(best.isRecommended, isTrue);
      expect(best.reason, '중앙 산개성단 관측 추천');
      expect(best.eyepiece?.focalLengthMm, 25);
      expect(best.screenFillPercent, greaterThan(0));
    });

    test('recommendForToday prioritizes equipment reason over condition', () {
      final m40 = object(id: 'm40', type: '쌍성', angularSize: "0.8'");
      final rec = RecommendationResult(
        object: m40,
        reasons: const [],
        season: '여름',
        score: 85,
        moonSeparation: 60,
      );

      final today = service.recommendForToday(
        object: m40,
        equipment: [seestarS30()],
        recommendation: rec,
      );

      expect(today.imaging, isNotNull);
      expect(today.imaging!.reason, '천체가 너무 작음');
      expect(today.imaging!.reason, isNot('현재 조건 최적'));
    });

    test('recommendForToday applies condition weighting', () {
      final rec = RecommendationResult(
        object: object(id: 'm42', type: '발광성운'),
        reasons: const [],
        season: '겨울',
        score: 85,
        moonSeparation: 60,
      );

      final condition = ObservationCondition(
        score: 80,
        siteName: 'Test',
        moon: const MoonInfo(
          age: 10,
          illumination: 0.7,
          phaseName: '상현',
          phaseEmoji: '🌓',
        ),
        cloudCover: 60,
        isObservationFeasible: false,
      );

      final today = service.recommendForToday(
        object: object(id: 'm42', type: '발광성운'),
        equipment: [seestarS30(), bcto90()],
        recommendation: rec,
        condition: condition,
      );

      expect(today.visual, isEmpty);
    });

    test('returns empty when no equipment registered', () {
      final result = service.recommendForObject(
        object: object(id: 'm42'),
        equipment: const [],
      );

      expect(result.hasRegisteredEquipment, isFalse);
      expect(result.imaging, isEmpty);
    });
  });
}
