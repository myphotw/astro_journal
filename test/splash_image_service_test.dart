import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:astro_journal/features/splash/data/splash_image_catalog.dart';
import 'package:astro_journal/services/splash_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('splash_img_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SplashImageCatalog', () {
    test('has stable ids and version', () {
      expect(SplashImageCatalog.catalogVersion, greaterThan(0));
      expect(SplashImageCatalog.entries, isNotEmpty);
      final ids = SplashImageCatalog.entries.map((e) => e.id).toSet();
      expect(ids.length, SplashImageCatalog.entries.length);
    });

    test('byTag returns seasonal subset', () {
      final winter = SplashImageCatalog.byTag('winter');
      expect(winter, isNotEmpty);
      expect(winter.every((e) => e.hasTag('winter')), isTrue);
    });
  });

  group('SplashImageService', () {
    test('downloads once, reuses local, avoids last id', () async {
      var downloads = 0;
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i + 1));
      final client = MockClient((request) async {
        downloads++;
        return http.Response.bytes(bytes, 200);
      });

      final service = SplashImageService(
        httpClient: client,
        random: math.Random(7),
        resolveCacheDirectory: () async => tempDir,
      );

      final first = await service.pickForDisplay();
      expect(first.isFallback, isFalse);
      expect(first.file, isNotNull);
      expect(await first.file!.exists(), isTrue);
      final firstId = first.entry!.id;
      expect(downloads, greaterThan(0));

      // pickForDisplay가 띄운 백그라운드 캐시까지 대기 후 검증
      await service.ensureCached();
      final jpgCount = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .length;
      expect(jpgCount, SplashImageCatalog.entries.length);

      final beforeSecond = downloads;
      final second = await service.pickForDisplay();
      await service.ensureCached();
      expect(second.isFallback, isFalse);
      expect(downloads, beforeSecond);
      expect(second.entry!.id, isNot(firstId));
      expect(p.basename(second.file!.path), second.entry!.fileName);
    });
  });
}
