import 'package:astro_journal/services/exposure_duration_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ExposureDurationParser();

  group('ExposureDurationParser', () {
    test('parses Korean minute-second format', () {
      expect(parser.parse('4분20초'), 260);
      expect(parser.parse('4분'), 240);
      expect(parser.parse('20초'), 20);
    });

    test('parses Korean hour-minute-second format', () {
      expect(parser.parse('1시간30분'), 5400);
      expect(parser.parse('2시간15분30초'), 8130);
    });

    test('parses minute suffix in English', () {
      expect(parser.parse('4.3 min'), closeTo(258, 0.001));
      expect(parser.parse('10 minutes'), 600);
    });

    test('parses plain numeric seconds', () {
      expect(parser.parse('260'), 260);
      expect(parser.parse('260.5'), 260.5);
    });

    test('returns zero for empty or invalid values', () {
      expect(parser.parse(''), 0);
      expect(parser.parse(null), 0);
      expect(parser.parse('invalid'), 0);
    });
  });
}
