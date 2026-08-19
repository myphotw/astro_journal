import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual Plate Solve remains visible for a remote Gallery photo', () {
    final record = ShootingRecord(
      id: 'remote:record-1',
      celestialObjectId: 'M54',
      capturedAt: DateTime(2026, 8, 19),
      createdAt: DateTime(2026, 8, 19),
      photoUri: '/api/astro/gallery/record-1/preview',
      backendFileId: 'sha-1',
      commonFileId: 178,
    );

    expect(record.isRemoteAsset, isTrue);
    expect(shouldShowManualPlateSolve(record), isTrue);
  });

  test('manual Plate Solve stays hidden when no photo exists', () {
    final record = ShootingRecord(
      id: 'manual-1',
      celestialObjectId: 'M54',
      capturedAt: DateTime(2026, 8, 19),
      createdAt: DateTime(2026, 8, 19),
    );

    expect(shouldShowManualPlateSolve(record), isFalse);
  });
}
