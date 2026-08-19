import 'dart:convert';

import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';
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
    late Uri requested;
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'data': _astroItemJson()}), 200);
      }),
    );

    final item = await source.getDetail('record-1');

    expect(requested.path, '/api/astro/gallery/record-1');
    expect(item.backendRecordId, 'record-1');
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
};
