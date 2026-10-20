import 'package:astro_journal/services/metadata_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('photo registration integration calculation', () {
    test('calculates total exposure from stack count and seconds', () {
      final minutes = MetadataFormat.integrationMinutesFromStackAndExposure(
        stackCount: '100',
        singleExposureSeconds: '20',
      );

      expect(minutes, '33.333333');
      expect(MetadataFormat.integrationSecondsFromMinutesInput(minutes!), 2000);
    });

    test('supports input order changes and decimal exposure', () {
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '120',
          singleExposureSeconds: '30',
        ),
        '60',
      );
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '90',
          singleExposureSeconds: '60',
        ),
        '90',
      );
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '13',
          singleExposureSeconds: '20.5',
        ),
        '4.441667',
      );
    });

    test('rejects empty, invalid, and negative source values', () {
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '',
          singleExposureSeconds: '20',
        ),
        isNull,
      );
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '10',
          singleExposureSeconds: 'invalid',
        ),
        isNull,
      );
      expect(
        MetadataFormat.integrationMinutesFromStackAndExposure(
          stackCount: '-1',
          singleExposureSeconds: '20',
        ),
        isNull,
      );
    });
  });
}
