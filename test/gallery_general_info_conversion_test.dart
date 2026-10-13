import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/services/metadata_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gallery integration converts UI minutes to rounded integer seconds', () {
    expect(MetadataFormat.integrationSecondsFromMinutesInput(''), isNull);
    expect(MetadataFormat.integrationSecondsFromMinutesInput('0'), 0);
    expect(MetadataFormat.integrationSecondsFromMinutesInput('1.25'), 75);
    expect(MetadataFormat.integrationSecondsFromMinutesInput('1.234'), 74);
  });

  test('unitless UI minutes are not parsed as stored seconds', () {
    expect(MetadataFormat.integrationSecondsFromMinutesInput('90'), 5400);
    expect(MetadataFormat.integrationSecondsFromExposure('90'), 90);
    expect(MetadataFormat.integrationSecondsFromExposure('1분30초'), 90);
  });

  test('legacy exif JSON remains readable without canonical Gallery fields', () {
    final exif = ExifInfo.fromJson(const {
      'filename': 'legacy.fit',
      'equipment': 'Legacy free text',
      'exposure': '30분',
    });

    expect(exif.equipment, 'Legacy free text');
    expect(exif.exposure, '30분');
    expect(exif.equipmentId, isNull);
    expect(exif.integrationSeconds, isNull);
  });

  test('canonical Gallery identity survives exif JSON round trip', () {
    const original = ExifInfo(
      filename: 'linked.fit',
      size: '',
      date: '',
      equipment: 'Canonical Draco',
      equipmentId: '11111111-1111-4111-8111-111111111111',
      equipmentNameSnapshot: 'Original Draco',
      equipmentIsActive: false,
      equipmentDeleted: true,
      focal: '',
      fstop: '',
      exposure: '1분15초',
      integrationSeconds: 75,
      iso: '',
      resolution: '',
      address: 'Stored address',
      addressIsCanonical: true,
    );

    final restored = ExifInfo.fromJson(original.toJson());

    expect(restored.equipmentId, original.equipmentId);
    expect(restored.equipmentNameSnapshot, 'Original Draco');
    expect(restored.equipmentDeleted, isTrue);
    expect(restored.integrationSeconds, 75);
    expect(restored.address, 'Stored address');
    expect(restored.addressIsCanonical, isTrue);
  });
}
