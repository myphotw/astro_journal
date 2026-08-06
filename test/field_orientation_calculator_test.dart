import 'package:astro_journal/data/models/fov_box.dart';
import 'package:astro_journal/data/models/representative_framing_size.dart';
import 'package:astro_journal/services/equipment/field_orientation_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldOrientationCalculator', () {
    const m31Framing = RepresentativeFramingSize(
      widthArcmin: 190,
      heightArcmin: 60,
      positionAngleDegrees: 35,
    );

    test('bestFramingFreeRotation matches M31 S30 rotated fit', () {
      final result = FieldOrientationCalculator.bestFramingFreeRotation(
        framing: m31Framing,
        fieldOfViewWidthDegrees: 2.24,
        fieldOfViewHeightDegrees: 3.99,
      );
      expect(result.bestCoverage, closeTo(0.79, 0.02));
      expect(result.recommendation, FramingRecommendation.good);
    });

    test('bestFramingDuringWindow finds sub-100% coverage over M31 transit', () {
      final result = FieldOrientationCalculator.bestFramingDuringWindow(
        framing: m31Framing,
        fieldOfViewWidthDegrees: 2.24,
        fieldOfViewHeightDegrees: 3.99,
        latitudeDeg: 37.5,
        longitudeDeg: 127.0,
        raHours: 0.7,
        declinationDeg: 41.27,
        windowStart: DateTime(2026, 10, 15, 20),
        windowEnd: DateTime(2026, 10, 16, 4),
      );
      expect(result.bestCoverage, lessThan(1.0));
    });
  });
}
