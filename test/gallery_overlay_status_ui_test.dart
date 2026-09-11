import 'dart:async';

import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/plate_solve_result.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/features/gallery/widgets/photo_overlay_view.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_detail_view_model.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/photo_overlay_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('Gallery Overlay status message', () {
    test('distinguishes pending and every unavailable reason', () {
      expect(
        galleryOverlayStatusMessage(overlay: null, isLoading: false),
        'Overlay 계산 대기 중',
      );
      expect(
        galleryOverlayStatusMessage(overlay: null, isLoading: true),
        'Overlay 계산 중...',
      );
      expect(
        galleryOverlayStatusMessage(
          overlay: const PhotoOverlayResult.unavailable(
            PhotoOverlayUnavailableReason.noPlateSolve,
          ),
          isLoading: false,
        ),
        'Plate Solve 결과를 사용할 수 없습니다.',
      );
      expect(
        galleryOverlayStatusMessage(
          overlay: const PhotoOverlayResult.unavailable(
            PhotoOverlayUnavailableReason.noImageSize,
          ),
          isLoading: false,
        ),
        '이미지 크기 정보를 확인할 수 없습니다.',
      );
      expect(
        galleryOverlayStatusMessage(
          overlay: const PhotoOverlayResult.unavailable(
            PhotoOverlayUnavailableReason.error,
          ),
          isLoading: false,
        ),
        'Overlay 계산 중 오류가 발생했습니다.',
      );
    });

    test('available Overlay has no error subtitle', () {
      expect(
        galleryOverlayStatusMessage(
          overlay: const PhotoOverlayResult(
            imageWidth: 2158,
            imageHeight: 3839,
            objects: [],
          ),
          isLoading: false,
        ),
        isNull,
      );
    });
  });

  testWidgets('open popup replaces loading text with the latest result', (
    tester,
  ) async {
    final record = ShootingRecord(
      id: 'local-m8',
      celestialObjectId: 'M8',
      capturedAt: DateTime.utc(2026, 9, 8),
      createdAt: DateTime.utc(2026, 9, 8),
      photoUri: '/missing-m8.jpg',
      plateSolve: PlateSolveResult.success(
        centerRa: 270.99267495060843,
        centerDec: -23.51232805578041,
        fovWidth: 2.2024437735212157,
        fovHeight: 3.9180637843132278,
        imageWidth: 2158,
        imageHeight: 3839,
      ),
    );
    final overlayService = _ControlledOverlayService();
    final detail = GalleryDetailViewModel(
      records: [record],
      initialIndex: 0,
      overlayService: overlayService,
    );
    final gallery = GalleryViewModel(
      _RecordRepository(record),
      _CatalogRepository(),
      CatalogSearchService(),
    );
    await gallery.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GalleryViewModel>.value(value: gallery),
          ChangeNotifierProvider<GalleryDetailViewModel>.value(value: detail),
        ],
        child: const MaterialApp(home: GalleryDetailScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('천체 Overlay 옵션'));
    // Advance the intentional Duration.zero yield in ensureOverlayLoaded so
    // the controlled service Future is definitely in flight.
    await tester.pump(const Duration(milliseconds: 1));

    expect(overlayService.calls, 1);
    expect(find.byKey(const Key('overlay-popup-loading')), findsOneWidget);
    expect(find.text('Overlay 계산 중...'), findsOneWidget);

    overlayService.complete(
      const PhotoOverlayResult.unavailable(
        PhotoOverlayUnavailableReason.noImageSize,
      ),
    );
    await tester.pump();
    expect(detail.isOverlayLoadingFor(record.id), isFalse);
    expect(
      detail.overlayFor(record.id)?.unavailableReason,
      PhotoOverlayUnavailableReason.noImageSize,
    );
    await tester.pump();

    expect(find.byKey(const Key('overlay-popup-loading')), findsNothing);
    expect(find.text('Overlay 계산 중...'), findsNothing);
    expect(find.text('Overlay 계산 대기 중'), findsNothing);
    expect(find.text('이미지 크기 정보를 확인할 수 없습니다.'), findsOneWidget);
  });

  testWidgets(
    'zoomed photo owns pan gestures and restores page swipe at base scale',
    (tester) async {
      final records = [
        ShootingRecord(
          id: 'gesture-one',
          celestialObjectId: 'M31',
          capturedAt: DateTime.utc(2026, 9, 10),
          createdAt: DateTime.utc(2026, 9, 10),
          photoUri: '/missing-gesture-one.jpg',
          plateSolve: PlateSolveResult.success(
            centerRa: 10.68,
            centerDec: 41.27,
            fovWidth: 2.2,
            fovHeight: 3.9,
            imageWidth: 1080,
            imageHeight: 1920,
          ),
        ),
        ShootingRecord(
          id: 'gesture-two',
          celestialObjectId: 'M42',
          capturedAt: DateTime.utc(2026, 9, 11),
          createdAt: DateTime.utc(2026, 9, 11),
          photoUri: '/missing-gesture-two.jpg',
        ),
      ];
      final detail = GalleryDetailViewModel(
        records: records,
        initialIndex: 0,
        overlayService: _ImmediateOverlayService(),
      );
      final gallery = GalleryViewModel(
        _RecordListRepository(records),
        _CatalogRepository(),
        CatalogSearchService(),
      );
      await gallery.load();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GalleryViewModel>.value(value: gallery),
            ChangeNotifierProvider<GalleryDetailViewModel>.value(value: detail),
          ],
          child: const MaterialApp(home: GalleryDetailScreen()),
        ),
      );
      await tester.pump();

      final pageViewFinder = find.byKey(const Key('gallery-detail-page-view'));
      final viewerFinder = find.byKey(
        const ValueKey<String>(
          'gallery-photo-interactive-/missing-gesture-one.jpg',
        ),
      );

      PageView pageView() => tester.widget<PageView>(pageViewFinder);
      TransformationController controller() => tester
          .widget<InteractiveViewer>(viewerFinder)
          .transformationController!;

      expect(pageView().physics, isA<ClampingScrollPhysics>());

      final zoomed = controller().value.clone()
        ..setIdentity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2);
      controller().value = zoomed;
      await tester.pump();

      expect(pageView().physics, isA<NeverScrollableScrollPhysics>());
      final translationBefore = controller().value.entry(0, 3);
      await tester.drag(viewerFinder, const Offset(-40, 0));
      await tester.pump();
      expect(controller().value.entry(0, 3), isNot(translationBefore));
      expect(detail.currentIndex, 0);

      controller().value = controller().value.clone()..setIdentity();
      await tester.pump();
      expect(pageView().physics, isA<ClampingScrollPhysics>());

      detail.toggleOverlayEnabled();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(
        find.descendant(
          of: viewerFinder,
          matching: find.byType(PhotoOverlayView),
        ),
        findsOneWidget,
      );

      controller().value = zoomed;
      await tester.pump();
      expect(pageView().physics, isA<NeverScrollableScrollPhysics>());
      final overlayTranslationBefore = controller().value.entry(0, 3);
      await tester.drag(viewerFinder, const Offset(-40, 0));
      await tester.pump();
      expect(controller().value.entry(0, 3), isNot(overlayTranslationBefore));
      expect(detail.currentIndex, 0);

      controller().value = controller().value.clone()..setIdentity();
      await tester.pump();
      expect(pageView().physics, isA<ClampingScrollPhysics>());

      await tester.drag(pageViewFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(detail.currentIndex, 1);
    },
  );
}

class _ControlledOverlayService extends PhotoOverlayService {
  _ControlledOverlayService() : super(_CatalogRepository());

  final Completer<PhotoOverlayResult> _result = Completer();
  int calls = 0;

  void complete(PhotoOverlayResult result) => _result.complete(result);

  @override
  Future<PhotoOverlayResult> buildOverlay(ShootingRecord record) {
    calls++;
    return _result.future;
  }
}

class _ImmediateOverlayService extends PhotoOverlayService {
  _ImmediateOverlayService() : super(_CatalogRepository());

  @override
  Future<PhotoOverlayResult> buildOverlay(ShootingRecord record) async {
    return const PhotoOverlayResult(
      imageWidth: 1080,
      imageHeight: 1920,
      objects: [],
    );
  }
}

class _RecordRepository extends Fake implements ShootingRecordRepository {
  _RecordRepository(this.record);

  final ShootingRecord record;

  @override
  Future<List<ShootingRecord>> getAll() async => [record];

  @override
  Future<ShootingRecord?> getById(String id) async =>
      id == record.id ? record : null;
}

class _RecordListRepository extends Fake implements ShootingRecordRepository {
  _RecordListRepository(this.records);

  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;

  @override
  Future<ShootingRecord?> getById(String id) async {
    for (final record in records) {
      if (record.id == id) return record;
    }
    return null;
  }
}

class _CatalogRepository extends Fake implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = false}) async => const [];
}
