import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_detail_view_model.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('one photo hides desktop navigation and the filmstrip', (
    tester,
  ) async {
    final records = _records(1);

    await _pumpGalleryDetail(tester, records, platform: TargetPlatform.windows);

    expect(find.byKey(const Key('gallery-filmstrip')), findsNothing);
    expect(find.byKey(const Key('gallery-previous-photo')), findsNothing);
    expect(find.byKey(const Key('gallery-next-photo')), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
  });

  testWidgets('desktop arrows and keyboard share the selected photo state', (
    tester,
  ) async {
    final records = _records(3);
    final detail = await _pumpGalleryDetail(
      tester,
      records,
      platform: TargetPlatform.windows,
    );

    expect(find.text('1 / 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-thumbnail-selected-0')),
      findsOneWidget,
    );
    expect(find.byTooltip('이전 사진'), findsOneWidget);
    expect(find.byTooltip('다음 사진'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('gallery-previous-photo')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(detail.currentIndex, 1);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-thumbnail-selected-1')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('다음 사진'));
    await tester.pumpAndSettle();
    expect(detail.currentIndex, 2);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const Key('gallery-next-photo')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(detail.currentIndex, 2);

    await tester.tap(find.byTooltip('이전 사진'));
    await tester.pumpAndSettle();
    expect(detail.currentIndex, 1);
  });

  testWidgets('desktop hover stays visible over thumbnails and hides on exit', (
    tester,
  ) async {
    final records = _records(3);
    final detail = await _pumpGalleryDetail(
      tester,
      records,
      platform: TargetPlatform.windows,
    );

    expect(_filmstripIgnoring(tester), isTrue);
    final mouse = await _hoverFilmstrip(tester);
    expect(_filmstripIgnoring(tester), isFalse);

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('gallery-thumbnail-selected-0')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_filmstripIgnoring(tester), isFalse);

    await tester.tap(find.byKey(const ValueKey('gallery-thumbnail-2')));
    await tester.pumpAndSettle();

    expect(detail.currentIndex, 2);
    expect(find.text('M3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-thumbnail-selected-2')),
      findsOneWidget,
    );

    await mouse.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_filmstripIgnoring(tester), isTrue);
    await mouse.removePointer();
  });

  testWidgets('mobile photo tap toggles the filmstrip without changing index', (
    tester,
  ) async {
    final records = _records(2);
    final detail = await _pumpGalleryDetail(
      tester,
      records,
      platform: TargetPlatform.android,
    );
    final photo = find.byKey(
      const ValueKey<String>('gallery-photo-interactive-/missing-photo-1.jpg'),
    );

    expect(_filmstripIgnoring(tester), isTrue);
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(_filmstripIgnoring(tester), isFalse);
    expect(detail.currentIndex, 0);

    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(_filmstripIgnoring(tester), isTrue);
    expect(detail.currentIndex, 0);

    final controller = tester
        .widget<InteractiveViewer>(photo)
        .transformationController!;
    controller.value = controller.value.clone()
      ..setIdentity()
      ..setEntry(0, 0, 2)
      ..setEntry(1, 1, 2);
    await tester.pump();
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(_filmstripIgnoring(tester), isTrue);
  });

  testWidgets('filmstrip scrolls horizontally on a narrow mobile layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final records = _records(10);

    await _pumpGalleryDetail(tester, records, platform: TargetPlatform.android);
    final photo = find.byKey(
      const ValueKey<String>('gallery-photo-interactive-/missing-photo-1.jpg'),
    );
    await tester.tap(photo);
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('gallery-filmstrip-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);

    await tester.drag(list, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('selected thumbnail automatically stays visible', (tester) async {
    tester.view.physicalSize = const Size(520, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final records = _records(10);

    await _pumpGalleryDetail(tester, records, platform: TargetPlatform.windows);
    final mouse = await _hoverFilmstrip(tester);

    for (var index = 1; index < records.length; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    final selected = find.byKey(const ValueKey('gallery-thumbnail-selected-9'));
    final list = find.byKey(const Key('gallery-filmstrip-list'));
    expect(selected, findsOneWidget);
    final listRect = tester.getRect(list);
    final selectedRect = tester.getRect(selected);
    expect(selectedRect.left, greaterThanOrEqualTo(listRect.left));
    expect(selectedRect.right, lessThanOrEqualTo(listRect.right));
    await mouse.removePointer();
  });

  testWidgets(
    'mobile swipe remains active and updates photo-specific details',
    (tester) async {
      final records = _records(2);
      final detail = await _pumpGalleryDetail(
        tester,
        records,
        platform: TargetPlatform.android,
      );

      expect(find.byKey(const Key('gallery-next-photo')), findsNothing);
      await tester.drag(
        find.byKey(const Key('gallery-detail-page-view')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      expect(detail.currentIndex, 1);
      expect(find.text('M2'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);

      await tester.tap(find.text('상세정보'));
      await tester.pumpAndSettle();
      expect(find.text('memo-2'), findsOneWidget);
    },
  );

  test('removing the selected photo keeps a valid neighboring index', () {
    final records = _records(3);
    final detail = GalleryDetailViewModel(records: records, initialIndex: 2);

    expect(detail.removeRecord(records[2].id), 2);
    expect(detail.currentIndex, 1);
    expect(detail.currentRecord.id, records[1].id);

    expect(detail.removeRecord(records[1].id), 1);
    expect(detail.currentIndex, 0);
    expect(detail.currentRecord.id, records[0].id);
  });
}

bool _filmstripIgnoring(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find.byKey(const Key('gallery-filmstrip-visibility')),
    )
    .ignoring;

Future<TestGesture> _hoverFilmstrip(WidgetTester tester) async {
  final region = find.byKey(const Key('gallery-filmstrip-hover-region'));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(10, 10));
  await mouse.moveTo(tester.getCenter(region));
  await tester.pumpAndSettle();
  return mouse;
}

Future<GalleryDetailViewModel> _pumpGalleryDetail(
  WidgetTester tester,
  List<ShootingRecord> records, {
  required TargetPlatform platform,
}) async {
  final detail = GalleryDetailViewModel(records: records, initialIndex: 0);
  final gallery = GalleryViewModel(
    _RecordRepository(records),
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
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: const GalleryDetailScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return detail;
}

List<ShootingRecord> _records(int count) => List.generate(
  count,
  (index) => ShootingRecord(
    id: 'record-${index + 1}',
    celestialObjectId: 'M${index + 1}',
    capturedAt: DateTime.utc(2026, 10, index + 1),
    createdAt: DateTime.utc(2026, 10, index + 1),
    photoUri: '/missing-photo-${index + 1}.jpg',
    thumbnailUrl: '/missing-thumbnail-${index + 1}.jpg',
    memo: 'memo-${index + 1}',
    isFavorite: index.isOdd,
  ),
);

class _RecordRepository extends Fake implements ShootingRecordRepository {
  _RecordRepository(this.records);

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
