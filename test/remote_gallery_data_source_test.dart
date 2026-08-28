import 'dart:convert';

import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';
import 'package:astro_journal/data/models/plate_solve_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses canonical Astro Gallery list fields', () async {
    late Uri requested;
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'items': [_astroItemJson()],
          }),
          200,
        );
      }),
    );

    final item = (await source.getGallery()).single;

    expect(requested.path, '/api/astro/gallery');
    expect(requested.path, isNot(contains('/api/common/gallery')));
    expect(item.backendRecordId, 'record-1');
    expect(item.revision, 7);
    expect(item.catalogObjectId, 'M42');
    expect(item.backendFileId, 'sha-1');
    expect(item.commonFileId, 178);
    expect(item.plateSolveStatus, PlateSolveQueueStatus.processing);
    expect(item.plateSolveJobId, 'opaque-job/token=');
    expect(item.favorite, isTrue);
    expect(item.representative, isTrue);
    expect(item.latitude, 33.3);
    expect(item.longitude, 126.5);
    expect(item.location, 'Jeju');
    expect(item.memo, 'canonical memo');
    expect(item.thumbnailUrl, '/media/thumb/sha-1');
    expect(item.previewUrl, '/media/preview/sha-1');
    expect(item.originalUrl, '/media/original/sha-1');
  });

  test('loads Astro Gallery detail by record_id', () async {
    final requestedPaths = <String>[];
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/api/astro/gallery/record-1') {
          return http.Response(jsonEncode({'data': _astroItemJson()}), 200);
        }
        return http.Response(
          jsonEncode({
            'record_id': 'record-1',
            'file_id': 178,
            'plate_solve_status': 'PROCESSING',
          }),
          200,
        );
      }),
    );

    final item = await source.getDetail('record-1');

    expect(requestedPaths, ['/api/astro/gallery/record-1']);
    expect(item.backendRecordId, 'record-1');
    expect(item.plateSolveStatus, PlateSolveQueueStatus.processing);
  });

  test(
    'recovers canonical common_file_id from ObservationRecord detail',
    () async {
      final requestedPaths = <String>[];
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);
      final galleryJson = _astroItemJson()..remove('common_file_id');
      final source = RemoteGalleryDataSource(
        baseUrl: 'https://backend.test',
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.url.path == '/api/astro/gallery/record-1') {
            return http.Response(jsonEncode(galleryJson), 200);
          }
          if (request.url.path == '/api/astro/records/record-1') {
            return http.Response(
              jsonEncode({
                'record_id': 'record-1',
                'file_id': 178,
                'plate_solve_status': 'WAITING',
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final item = await source.getDetail('record-1');

      expect(requestedPaths, [
        '/api/astro/gallery/record-1',
        '/api/astro/records/record-1',
      ]);
      expect(item.backendRecordId, 'record-1');
      expect(item.backendFileId, 'sha-1');
      expect(item.commonFileId, 178);
      expect(item.plateSolveStatus, PlateSolveQueueStatus.waiting);
      expect(logs, contains(contains('backend_record_id=record-1')));
      expect(logs, contains(contains('http=success')));
      expect(logs, contains(contains('file_id_present=true')));
      expect(logs, contains(contains('file_id_type=int')));
      expect(logs, contains(contains('parsed_common_file_id=178')));
    },
  );

  test('hydrates COMPLETED persistent result from Gallery detail', () async {
    final detail = _astroItemJson()
      ..['plate_solve_status'] = 'COMPLETED'
      ..['plate_solve_result'] = {
        'ra': 83.822,
        'dec': -5.391,
        'rotation': 11.5,
        'pixel_scale': 2.3,
        'field_width': 1.8,
        'field_height': 1.2,
        'parity': -1,
      };
    final requestedPaths = <String>[];
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response(jsonEncode({'data': detail}), 200);
      }),
    );

    final item = await source.getDetail('record-1');

    expect(requestedPaths, ['/api/astro/gallery/record-1']);
    expect(item.plateSolveJobId, 'opaque-job/token=');
    expect(item.plateSolve?.centerRa, 83.822);
    expect(item.plateSolve?.centerDec, -5.391);
    expect(item.plateSolve?.fovWidth, 1.8);
    expect(item.plateSolve?.fovHeight, 1.2);
  });

  test('hydrates persistent result from Observation detail fallback', () async {
    final gallery = _astroItemJson()
      ..remove('plate_solve_status')
      ..remove('plate_solve_job_id');
    final requestedPaths = <String>[];
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/api/astro/gallery/record-1') {
          return http.Response(jsonEncode({'data': gallery}), 200);
        }
        return http.Response(
          jsonEncode({
            'record_id': 'record-1',
            'file_id': 178,
            'plate_solve_status': 'COMPLETED',
            'plate_solve_job_id': 'observation-job',
            'plate_solve_result': {'ra': 10.5, 'dec': -20.25},
          }),
          200,
        );
      }),
    );

    final item = await source.getDetail('record-1');

    expect(requestedPaths, [
      '/api/astro/gallery/record-1',
      '/api/astro/records/record-1',
    ]);
    expect(item.plateSolveStatus, PlateSolveQueueStatus.completed);
    expect(item.plateSolveJobId, 'observation-job');
    expect(item.plateSolve?.centerRa, 10.5);
    expect(item.plateSolve?.centerDec, -20.25);
  });

  test(
    'never substitutes record_id or SHA file_id for common_file_id',
    () async {
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);
      final galleryJson = _astroItemJson()..remove('common_file_id');
      final source = RemoteGalleryDataSource(
        baseUrl: 'https://backend.test',
        client: MockClient((request) async {
          if (request.url.path.startsWith('/api/astro/gallery/')) {
            return http.Response(jsonEncode(galleryJson), 200);
          }
          return http.Response(
            jsonEncode({'record_id': 'record-1', 'file_id': 'sha-1'}),
            200,
          );
        }),
      );

      final item = await source.getDetail('record-1');

      expect(item.backendRecordId, 'record-1');
      expect(item.backendFileId, 'sha-1');
      expect(item.commonFileId, isNull);
      expect(logs, contains(contains('file_id_type=String')));
      expect(logs, contains(contains('parsed_common_file_id=null')));
    },
  );

  test('logs recovery HTTP failure without URL or secrets', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);
    final galleryJson = _astroItemJson()..remove('common_file_id');
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        if (request.url.path.startsWith('/api/astro/gallery/')) {
          return http.Response(jsonEncode(galleryJson), 200);
        }
        return http.Response('unavailable', 503);
      }),
    );

    final item = await source.getDetail('record-1');

    expect(item.commonFileId, isNull);
    expect(logs, contains(contains('http=failure status_code=503')));
    expect(logs.join('\n'), isNot(contains('https://')));
    expect(logs.join('\n'), isNot(contains('Authorization')));
  });
}

Map<String, dynamic> _astroItemJson() => {
  'record_id': 'record-1',
  'revision': 7,
  'catalog_object_id': 'M42',
  'captured_at': '2026-08-07T01:02:03Z',
  'latitude': 33.3,
  'longitude': 126.5,
  'location_name': 'Jeju',
  'memo': 'canonical memo',
  'favorite': true,
  'representative': true,
  'file_id': 'sha-1',
  'common_file_id': 178,
  'filename': 'm42.fit',
  'mime_type': 'image/fits',
  'thumbnail_url': '/media/thumb/sha-1',
  'preview_url': '/media/preview/sha-1',
  'original_url': '/media/original/sha-1',
  'capture_datetime': '2026-08-07T01:01:00Z',
  'plate_solve_status': 'PROCESSING',
  'plate_solve_job_id': 'opaque-job/token=',
};
