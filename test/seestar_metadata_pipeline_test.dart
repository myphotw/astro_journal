import 'dart:convert';
import 'dart:io';

import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/services/metadata_service.dart';
import 'package:astro_journal/services/photo_metadata_pipeline.dart';
import 'package:astro_journal/services/seestar_json_parser.dart';
import 'package:astro_journal/services/seestar_maker_note_parser.dart';
import 'package:astro_journal/services/seestar_metadata_pipeline.dart';
import 'package:astro_journal/services/seestar_owner_name_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Seestar M27 sample — MakerNote → Metadata pipeline', () {
    late String makerNoteJson;
    late File sampleImage;

    setUpAll(() {
      makerNoteJson = File('test/fixtures/seestar_m27_maker_note.json')
          .readAsStringSync()
          .trim();
      sampleImage = File('test/fixtures/seestar_m27_sample.jpg');
    });

    test('uploaded chat image has no embedded EXIF (APP1 stripped)', () {
      expect(sampleImage.existsSync(), isTrue);
      final bytes = sampleImage.readAsBytesSync();
      final hasApp1 = _hasJpegMarker(bytes, 0xE1);
      final ascii = String.fromCharCodes(bytes);
      expect(hasApp1, isFalse, reason: 'Cursor chat upload removes EXIF');
      expect(ascii.contains('obj_name'), isFalse);
    });

    test('SeestarJsonParser.parse extracts all core fields', () {
      const parser = SeestarJsonParser();
      final result = parser.parse(makerNoteJson, source: 'MakerNote');

      expect(result, isNotNull);
      expect(result!.objName, 'M 27');
      expect(result.date, '2026-06-13 00:40:10');
      expect(result.creator, 'ZWO Seestar S30 Pro');
      expect(result.lat, closeTo(37.493301, 0.000001));
      expect(result.lng, closeTo(126.872002, 0.000001));
      expect(result.stackNum, 13);
      expect(result.expSec, 20.0);
      expect(result.totExpSec, 260.0);
    });

    test('SeestarMakerNoteParser.parse via pipeline', () {
      const pipeline = SeestarMetadataPipeline();
      final result = pipeline.parseMakerNote(makerNoteJson);

      expect(result, isNotNull);
      expect(result!.objName, 'M 27');
      expect(result.stackNum, 13);
      expect(result.expSec, 20.0);
      expect(result.totExpSec, 260.0);
    });

    test('CameraOwnerName uses same SeestarJsonParser', () {
      const ownerParser = SeestarOwnerNameParser();
      final result = ownerParser.parse(makerNoteJson, source: 'CameraOwnerName');

      expect(result, isNotNull);
      expect(result!.objName, 'M 27');
      expect(result.totExpSec, 260.0);
    });

    test('MetadataService.merge maps to PhotoMetadata', () {
      const pipeline = SeestarMetadataPipeline();
      const metadataService = MetadataService();
      final seestar = pipeline.parseMakerNote(makerNoteJson)!;

      final merged = metadataService.merge(
        exif: const ExifInfo(
          filename: 'Stacked_13_M 27_20.0s_LP_20260613-004010.jpg',
          originalFilename: 'Stacked_13_M 27_20.0s_LP_20260613-004010.jpg',
          size: '1.0 MB',
          date: '',
          equipment: 'ZWO Seestar S30 Pro',
          focal: '160 mm',
          fstop: 'f/5',
          exposure: '4.3 min',
          iso: 'ISO 200',
          resolution: '1920 × 1080',
          makerNoteJson: null,
        ).copyWith(makerNoteJson: makerNoteJson),
        makerNote: seestar,
      );

      expect(merged.targetName, 'M 27');
      expect(merged.capturedAt, isNotNull);
      expect(merged.capturedAt, contains('2026-06-13'));
      expect(merged.equipment, 'ZWO Seestar S30 Pro');
      expect(merged.lat, closeTo(37.493301, 0.000001));
      expect(merged.lng, closeTo(126.872002, 0.000001));
      expect(merged.stackNum, 13);
      expect(merged.singleExpSec, '20초');
      expect(merged.exposure, '4분20초');
    });

    test('PhotoMetadataPipeline enriches ExifInfo', () async {
      final photoPipeline = PhotoMetadataPipeline();
      const originalFilename = 'Stacked_13_M 27_20.0s_LP_20260613-004010.jpg';

      final result = await photoPipeline.process(
        exif: const ExifInfo(
          filename: '',
          size: '1.0 MB',
          date: '',
          equipment: 'ZWO Seestar S30 Pro',
          focal: '160 mm',
          fstop: 'f/5',
          exposure: '4.3 min',
          iso: 'ISO 200',
          resolution: '1920 × 1080',
        ).copyWith(makerNoteJson: makerNoteJson),
        originalFilename: originalFilename,
      );

      expect(result.metadata.targetName, 'M 27');
      expect(result.exifInfo.targetName, 'M 27');
      expect(result.exifInfo.stackNum, 13);
      expect(result.exifInfo.singleExpSec, '20초');
      expect(result.exifInfo.exposure, '4분20초');
      expect(result.exifInfo.originalFilename, originalFilename);
      expect(result.exifInfo.lat, closeTo(37.493301, 0.000001));
      expect(result.exifInfo.lng, closeTo(126.872002, 0.000001));
    });

    test('MakerNote with binary prefix still parses', () {
      const parser = SeestarMakerNoteParser();
      final prefixed = 'ZWO\x00${jsonEncode(jsonDecode(makerNoteJson))}';
      final result = parser.parse(prefixed);

      expect(result, isNotNull);
      expect(result!.objName, 'M 27');
      expect(result.totExpSec, 260.0);
    });

    test('SeestarJsonParser.parse unwraps result nested JSON', () {
      const parser = SeestarJsonParser();
      final wrapped = jsonEncode({
        'result': jsonDecode(makerNoteJson),
        'code': 0,
      });
      final result = parser.parse(wrapped, source: 'MakerNote');

      expect(result, isNotNull);
      expect(result!.objName, 'M 27');
      expect(result.date, '2026-06-13 00:40:10');
      expect(result.creator, 'ZWO Seestar S30 Pro');
      expect(result.stackNum, 13);
      expect(result.expSec, 20.0);
      expect(result.totExpSec, 260.0);
    });
  });
}

bool _hasJpegMarker(List<int> bytes, int marker) {
  for (var i = 0; i < bytes.length - 1; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == marker) {
      return true;
    }
  }
  return false;
}
