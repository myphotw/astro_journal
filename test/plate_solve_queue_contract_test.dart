import 'package:astro_journal/data/models/gallery_item.dart';
import 'package:astro_journal/data/models/gallery_observation_projection.dart';
import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/core/constants/analysis_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final shaA = List.filled(64, 'a').join();
  final shaOne = List.filled(64, '1').join();

  test('WAITING PROCESSING COMPLETED FAILED map exactly', () {
    expect(
      PlateSolveQueueStatus.fromJson('WAITING'),
      PlateSolveQueueStatus.waiting,
    );
    expect(
      PlateSolveQueueStatus.fromJson('PROCESSING'),
      PlateSolveQueueStatus.processing,
    );
    expect(
      PlateSolveQueueStatus.fromJson('COMPLETED'),
      PlateSolveQueueStatus.completed,
    );
    expect(
      PlateSolveQueueStatus.fromJson('FAILED'),
      PlateSolveQueueStatus.failed,
    );
    expect(PlateSolveQueueStatus.fromJson(null), isNull);
    expect(PlateSolveQueueStatus.fromJson('UNKNOWN'), isNull);
  });

  test('Gallery projection preserves numeric identity and queue status', () {
    final item = GalleryItem.fromJson({
      'record_id': 'record-1',
      'revision': 3,
      'catalog_object_id': 'M42',
      'captured_at': '2026-08-28T00:00:00Z',
      'favorite': false,
      'representative': false,
      'file_id': shaA,
      'common_file_id': 178,
      'plate_solve_status': 'PROCESSING',
      'plate_solve_job_id': 'opaque-job/token=',
      'thumbnail_url': '/thumbnail',
      'preview_url': '/preview',
      'original_url': '/original',
    });

    final record = GalleryObservationProjection.fromGalleryItem(
      item,
    ).toShootingRecord();

    expect(record.id, 'remote:record-1');
    expect(record.backendFileId, shaA);
    expect(record.commonFileId, 178);
    expect(record.plateSolveQueueStatus, PlateSolveQueueStatus.processing);
    expect(record.plateSolveJobId, 'opaque-job/token=');
    expect(record.analysisStatus, AnalysisStatus.processing);
  });

  test('SHA file_id is never parsed as numeric common_file_id', () {
    final item = GalleryItem.fromJson({
      'record_id': 'record-1',
      'revision': 3,
      'catalog_object_id': 'M42',
      'captured_at': '2026-08-28T00:00:00Z',
      'favorite': false,
      'representative': false,
      'file_id': shaOne,
      'thumbnail_url': '/thumbnail',
      'preview_url': '/preview',
      'original_url': '/original',
    });

    expect(item.backendFileId, shaOne);
    expect(item.commonFileId, isNull);
  });

  test('COMPLETED projection preserves an already hydrated WCS result', () {
    final local = ShootingRecord(
      id: 'local-1',
      celestialObjectId: 'M42',
      capturedAt: DateTime.utc(2026, 8, 28),
      createdAt: DateTime.utc(2026, 8, 28),
      plateSolve: PlateSolveResult.success(
        centerRa: 83.8,
        centerDec: -5.4,
        rotation: 12,
        pixelScale: 2.1,
      ),
    );
    final item = GalleryItem.fromJson({
      'record_id': 'record-1',
      'revision': 4,
      'catalog_object_id': 'M42',
      'captured_at': '2026-08-28T00:00:00Z',
      'favorite': false,
      'representative': false,
      'file_id': shaA,
      'common_file_id': 178,
      'plate_solve_status': 'COMPLETED',
      'thumbnail_url': '/thumbnail',
      'preview_url': '/preview',
      'original_url': '/original',
    });

    final record = GalleryObservationProjection.fromGalleryItem(
      item,
    ).toShootingRecord(localRecord: local);

    expect(record.plateSolveQueueStatus, PlateSolveQueueStatus.completed);
    expect(record.plateSolve?.success, isTrue);
    expect(record.plateSolve?.centerRa, 83.8);
  });

  test('persistent backend result hydrates the canonical WCS consumer', () {
    final item = GalleryItem.fromJson({
      'record_id': 'record-1',
      'revision': 5,
      'catalog_object_id': 'M42',
      'captured_at': '2026-08-28T00:00:00Z',
      'favorite': false,
      'representative': false,
      'file_id': shaA,
      'common_file_id': 178,
      'plate_solve_status': 'COMPLETED',
      'plate_solve_job_id': 'opaque-job/token=',
      'plate_solve_result': {
        'ra': 83.822,
        'dec': -5.391,
        'rotation': 12.5,
        'pixel_scale': 2.3,
        'field_width': 1.8,
        'field_height': 1.2,
        'parity': -1,
      },
      'thumbnail_url': '/thumbnail',
      'preview_url': '/preview',
      'original_url': '/original',
    });

    final projection = GalleryObservationProjection.fromGalleryItem(item);
    final record = projection.toShootingRecord();

    expect(projection.plateSolveJobId, 'opaque-job/token=');
    expect(record.plateSolveJobId, 'opaque-job/token=');
    expect(record.plateSolve, same(projection.plateSolve));
    expect(record.plateSolve?.centerRa, 83.822);
    expect(record.plateSolve?.centerDec, -5.391);
    expect(record.plateSolve?.rotation, 12.5);
    expect(record.plateSolve?.pixelScale, 2.3);
    expect(record.plateSolve?.fovWidth, 1.8);
    expect(record.plateSolve?.fovHeight, 1.2);
    expect(record.plateSolve?.parity, -1);
  });

  test('backend COMPLETED result replaces an older local WCS result', () {
    final local = ShootingRecord(
      id: 'local-1',
      celestialObjectId: 'M42',
      capturedAt: DateTime.utc(2026, 8, 28),
      createdAt: DateTime.utc(2026, 8, 28),
      plateSolve: PlateSolveResult.success(centerRa: 1, centerDec: 2),
    );
    final item = GalleryItem.fromJson({
      'record_id': 'record-1',
      'revision': 6,
      'catalog_object_id': 'M42',
      'captured_at': '2026-08-28T00:00:00Z',
      'favorite': false,
      'representative': false,
      'file_id': shaA,
      'common_file_id': 178,
      'plate_solve_status': 'COMPLETED',
      'plate_solve_job_id': 'job-1',
      'plate_solve_result': {'ra': 83.8, 'dec': -5.4},
      'thumbnail_url': '/thumbnail',
      'preview_url': '/preview',
      'original_url': '/original',
    });

    final record = GalleryObservationProjection.fromGalleryItem(
      item,
    ).toShootingRecord(localRecord: local);

    expect(record.plateSolve?.centerRa, 83.8);
    expect(record.plateSolve?.centerDec, -5.4);
  });
}
