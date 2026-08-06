import 'package:astro_journal/features/light_pollution_map/overlay/brightness_color_mapper.dart';
import 'package:astro_journal/features/light_pollution_map/overlay/light_pollution_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LightPollutionScale', () {
    test('inner-city artificial brightness maps to Bortle 9', () {
      expect(LightPollutionScale.artificialMcdToBortle(5.0), 9);
      expect(LightPollutionScale.artificialMcdToBortle(6.5), 9);
      expect(LightPollutionScale.artificialMcdToBortle(12.0), 9);
    });

    test('Gurye reference area brightness maps to Bortle 4', () {
      for (final brightness in [0.22, 0.28, 0.32, 0.35]) {
        expect(
          LightPollutionScale.artificialMcdToBortle(brightness),
          4,
          reason: 'brightness=$brightness',
        );
      }
    });

    test('Bortle 4 sub-tiers distinguish dark, mid, and bright bins', () {
      expect(LightPollutionScale.bortle4SubTier(0.06), Bortle4SubTier.dark);
      expect(LightPollutionScale.bortle4SubTier(0.10), Bortle4SubTier.dark);
      expect(LightPollutionScale.bortle4SubTier(0.15), Bortle4SubTier.mid);
      expect(LightPollutionScale.bortle4SubTier(0.22), Bortle4SubTier.mid);
      expect(LightPollutionScale.bortle4SubTier(0.28), Bortle4SubTier.bright);
      expect(LightPollutionScale.bortle4SubTier(0.35), Bortle4SubTier.bright);
      expect(LightPollutionScale.bortle4SubTier(0.55), isNull);
    });

    test('Bortle 4 sub-tiers map to distinct overlay colors', () {
      final dark = BrightnessColorMapper.legendEntryFor(0.06);
      final mid = BrightnessColorMapper.legendEntryFor(0.22);
      final bright = BrightnessColorMapper.legendEntryFor(0.28);

      expect(dark.bortle4SubTier, Bortle4SubTier.dark);
      expect(mid.bortle4SubTier, Bortle4SubTier.mid);
      expect(bright.bortle4SubTier, Bortle4SubTier.bright);
      expect(dark.color, isNot(equals(mid.color)));
      expect(mid.color, isNot(equals(bright.color)));
    });

    test('Falchi bins spread rural-to-suburban brightness across bortle classes', () {
      final samples = <double, int>{
        0.002: 1, // bin 2
        0.015: 3, // bin 5
        0.06: 4, // bin 6
        0.15: 4, // bin 8
        0.28: 4, // bin 9 — Gurye
        0.55: 5, // bin 10
        1.2: 6, // bin 11
        2.8: 8, // bin 12 + bright-city floor
        4.5: 9, // bin 14 — urban core
      };

      for (final entry in samples.entries) {
        expect(
          LightPollutionScale.artificialMcdToBortle(entry.key),
          entry.value,
          reason: 'brightness=${entry.key}',
        );
      }
    });

    test('Seoul-like brightness is labeled as urban core', () {
      const seoulLike = 6.2;
      final bortle = LightPollutionScale.artificialMcdToBortle(seoulLike);
      final entry = BrightnessColorMapper.legendEntryFor(seoulLike);

      expect(bortle, 9);
      expect(entry.bortle, 9);
      expect(entry.label, contains('도시'));
    });

    test('legend includes three Bortle 4 sub-tier entries', () {
      expect(BrightnessColorMapper.legendEntries.length, 11);
      final bortle4Entries = BrightnessColorMapper.legendEntries
          .where((entry) => entry.bortle == 4)
          .toList(growable: false);
      expect(bortle4Entries.length, 3);
      expect(
        bortle4Entries.map((entry) => entry.bortle4SubTier),
        [
          Bortle4SubTier.dark,
          Bortle4SubTier.mid,
          Bortle4SubTier.bright,
        ],
      );
    });

    test('bortleDisplayLabel includes Bortle 4 sub-tier label', () {
      expect(
        LightPollutionScale.bortleDisplayLabel(4, artificialMcd: 0.06),
        'Bortle 4 · 시골·교외 · 어두움',
      );
      expect(
        LightPollutionScale.bortleDisplayLabel(4, artificialMcd: 0.22),
        'Bortle 4 · 시골·교외 · 보통',
      );
      expect(
        LightPollutionScale.bortleDisplayLabel(4, artificialMcd: 0.28),
        'Bortle 4 · 시골·교외 · 밝음',
      );
    });

    test('Falchi ratio bin matches Table 1 for urban brightness', () {
      final ratio = LightPollutionScale.artificialRatio(6.2);
      expect(ratio, greaterThan(20.5));
      expect(LightPollutionScale.falchiColorBin(6.2), greaterThanOrEqualTo(12));
    });

    test('falchiBinToBortle covers all 14 atlas bins', () {
      expect(LightPollutionScale.falchiBinToBortle.length, 14);
      for (final bortle in LightPollutionScale.falchiBinToBortle) {
        expect(bortle, inInclusiveRange(1, 9));
      }
    });
  });
}
