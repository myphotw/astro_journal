import 'package:astro_journal/core/constants/astro_season.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/services/season_planner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = SeasonPlannerService();

  const summerNebula = CatalogObject(
    id: 'M8',
    number: 8,
    catalog: CatalogType.messier,
    name: 'Lagoon Nebula',
    type: '성운',
    constellation: '궁수',
    ra: '18h 03m 37s',
    dec: '-24° 23\'',
    magnitude: '6.0',
  );

  const winterNebula = CatalogObject(
    id: 'M42',
    number: 42,
    catalog: CatalogType.messier,
    name: 'Orion Nebula',
    type: '성운',
    constellation: '오리온',
    ra: '05h 35m 17s',
    dec: '-05° 23\'',
    magnitude: '4.0',
  );

  group('SeasonPlannerService', () {
    test('여름 성운은 여름 점수가 겨울보다 높다', () {
      final summerScore = service.scoreForSeason(
        summerNebula,
        AstroSeason.summer,
      );
      final winterScore = service.scoreForSeason(
        summerNebula,
        AstroSeason.winter,
      );

      expect(summerScore, greaterThan(winterScore));
    });

    test('겨울 성운은 겨울 점수가 여름보다 높다', () {
      final summerScore = service.scoreForSeason(
        winterNebula,
        AstroSeason.summer,
      );
      final winterScore = service.scoreForSeason(
        winterNebula,
        AstroSeason.winter,
      );

      expect(winterScore, greaterThan(summerScore));
    });

    test('태양계 대상은 계절 플래너에서 제외된다', () {
      const solar = CatalogObject(
        id: 'jupiter',
        number: 5,
        catalog: CatalogType.solar,
        name: '목성',
        type: '행성',
        constellation: '-',
        ra: '-',
        dec: '-',
        magnitude: '-2.0',
      );

      expect(SeasonPlannerService.isSeasonPlannerEligible(solar), isFalse);
      expect(service.scoreForMonth(solar, 7), 0);
    });

    test('buildItems는 점수 내림차순으로 정렬한다', () {
      final items = service.buildItems(
        objects: [winterNebula, summerNebula],
        month: 7,
        minScore: 0,
      );

      expect(items.length, 1);
      expect(items.first.object.id, 'M8');
    });

    test('월별 모드에서는 최적 월이 선택한 달과 같은 대상만 포함한다', () {
      const springPeakNebula = CatalogObject(
        id: 'RCW98',
        number: 98,
        catalog: CatalogType.rcw,
        name: 'RCW 98',
        type: '발광성운',
        constellation: '센타우루스',
        ra: '15h 55m',
        dec: '-54°39\'',
        magnitude: '-',
      );

      final julyItems = service.buildItems(
        objects: [springPeakNebula, summerNebula],
        month: 7,
        minScore: 0,
      );

      expect(julyItems.any((item) => item.object.id == 'RCW98'), isFalse);
      expect(julyItems.any((item) => item.object.id == 'M8'), isTrue);

      final mayItems = service.buildItems(
        objects: [springPeakNebula],
        month: 5,
        minScore: 0,
      );
      expect(mayItems.any((item) => item.object.id == 'RCW98'), isTrue);
    });

    test('catalogFilters로 선택 카탈로그만 포함한다', () {
      const ngc = CatalogObject(
        id: 'NGC7000',
        number: 7000,
        catalog: CatalogType.ngc,
        name: 'North America Nebula',
        type: '성운',
        constellation: '백조',
        ra: '20h 59m 17s',
        dec: '+44° 31\'',
        magnitude: '4.0',
      );

      final items = service.buildItems(
        objects: [summerNebula, ngc],
        month: 7,
        minScore: 0,
        catalogFilters: {CatalogType.messier},
      );

      expect(items.every((item) => item.object.catalog == CatalogType.messier),
          isTrue);
      expect(items.any((item) => item.object.id == 'M8'), isTrue);
    });

    test('summarize는 미촬영 수를 집계한다', () {
      final capturedSummer = summerNebula.copyWith(captured: true);
      final summary = service.summarize(
        objects: [capturedSummer, winterNebula],
        month: 7,
        season: AstroSeason.summer,
        minScore: 0,
      );

      expect(summary.total, 1);
      expect(summary.uncaptured, 0);
    });

    test('계절 모드에서는 최적 월이 해당 계절에 속한 대상만 포함한다', () {
      const springPeakNebula = CatalogObject(
        id: 'RCW98',
        number: 98,
        catalog: CatalogType.rcw,
        name: 'RCW 98',
        type: '발광성운',
        constellation: '센타우루스',
        ra: '15h 55m',
        dec: '-54°39\'',
        magnitude: '-',
      );

      expect(service.peakMonth(springPeakNebula), 5);

      final summerItems = service.buildItems(
        objects: [springPeakNebula, summerNebula],
        month: 7,
        season: AstroSeason.summer,
        minScore: 0,
      );

      expect(summerItems.any((item) => item.object.id == 'RCW98'), isFalse);
      expect(summerItems.any((item) => item.object.id == 'M8'), isTrue);

      final springItems = service.buildItems(
        objects: [springPeakNebula],
        month: 5,
        season: AstroSeason.spring,
        minScore: 0,
      );
      expect(springItems.any((item) => item.object.id == 'RCW98'), isTrue);
    });

    test('RCW·vdB with RA are included in season planner items', () {
      const rcw = CatalogObject(
        id: 'RCW57',
        number: 57,
        catalog: CatalogType.rcw,
        name: 'RCW 57',
        type: '발광성운',
        constellation: '센타우루스',
        ra: '11h 15m',
        dec: '-61°12\'',
        magnitude: '-',
      );
      const vdb = CatalogObject(
        id: 'vdB31',
        number: 31,
        catalog: CatalogType.vdb,
        name: 'vdB 31',
        type: '반사성운',
        constellation: '오리온',
        ra: '04h 56m',
        dec: '+30°33\'',
        magnitude: '-',
      );

      final rcwPeak = service.peakMonth(rcw);
      final vdbPeak = service.peakMonth(vdb);

      final rcwItems = service.buildItems(
        objects: [rcw],
        month: rcwPeak,
        minScore: 0,
      );
      final vdbItems = service.buildItems(
        objects: [vdb],
        month: vdbPeak,
        minScore: 0,
      );

      expect(rcwItems.length, 1);
      expect(vdbItems.length, 1);
      expect(rcwItems.first.object.catalog, CatalogType.rcw);
      expect(vdbItems.first.object.catalog, CatalogType.vdb);
    });

    test('computeSeasonFields는 RA 기준 계절 라벨을 만든다', () {
      final fields = service.computeSeasonFields(summerNebula);
      expect(fields, isNotNull);
      expect(fields!.peakMonth, inInclusiveRange(6, 8));
      expect(fields.label, contains('여름'));
    });

    test('RA 없는 대상은 계절 필드를 만들지 않는다', () {
      const noRa = CatalogObject(
        id: 'custom',
        number: 1,
        catalog: CatalogType.ngc,
        name: 'Custom',
        type: '성운',
        constellation: '-',
        ra: '',
        dec: '',
        magnitude: '-',
      );

      expect(service.computeSeasonFields(noRa), isNull);
    });
  });
}
