import 'dart:convert';

import 'package:astro_journal/data/datasources/remote_gallery_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('calls all TC-Backend common gallery endpoints', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      requested.add(request.url.path);
      switch (request.url.path) {
        case '/api/common/gallery':
        case '/api/common/gallery/search':
          return http.Response(
            jsonEncode({
              'items': [
                {'file_id': 'file-1'},
              ],
            }),
            200,
          );
        case '/api/common/gallery/file-1':
          return http.Response(jsonEncode({'file_id': 'file-1'}), 200);
        case '/api/common/gallery/timeline':
          return http.Response(jsonEncode({'buckets': []}), 200);
        case '/api/common/gallery/statistics':
          return http.Response(jsonEncode({'total': 1}), 200);
      }
      return http.Response('not found', 404);
    });
    final source = RemoteGalleryDataSource(
      baseUrl: 'https://backend.test',
      client: client,
    );

    expect((await source.getGallery()).single.backendFileId, 'file-1');
    expect((await source.getDetail('file-1')).backendFileId, 'file-1');
    expect((await source.search('M42')).single.backendFileId, 'file-1');
    expect(await source.getTimeline(), {'buckets': []});
    expect(await source.getStatistics(), {'total': 1});
    expect(requested, [
      '/api/common/gallery',
      '/api/common/gallery/file-1',
      '/api/common/gallery/search',
      '/api/common/gallery/timeline',
      '/api/common/gallery/statistics',
    ]);
  });
}
