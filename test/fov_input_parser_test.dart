import 'package:astro_journal/core/utils/fov_input_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FovInputParser', () {
    test('parses multiply separator', () {
      expect(
        FovInputParser.parsePair('0.72×1.28'),
        (0.72, 1.28),
      );
    });

    test('parses x separator with spaces', () {
      expect(
        FovInputParser.parsePair('2.24 x 3.99'),
        (2.24, 3.99),
      );
    });

    test('parses single value as square FOV', () {
      expect(
        FovInputParser.parsePair('4.6'),
        (4.6, 4.6),
      );
    });

    test('formats pair label', () {
      expect(
        FovInputParser.formatPair(0.72, 1.28),
        '0.72×1.28°',
      );
      expect(
        FovInputParser.formatPair(2.24, 3.99),
        '2.24×3.99°',
      );
    });
  });
}
