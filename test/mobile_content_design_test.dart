import 'dart:async';

import 'package:astro_journal/core/constants/catalog_kind_filter.dart';
import 'package:astro_journal/core/constants/catalog_sort_order.dart';
import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/catalog_display_scope.dart';
import 'package:astro_journal/core/constants/gallery_object_category.dart';
import 'package:astro_journal/core/navigation/app_navigation_notifier.dart';
import 'package:astro_journal/core/theme/app_theme.dart';
import 'package:astro_journal/core/theme/pc_design.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/season_planner_item.dart';
import 'package:astro_journal/data/models/shooting_record.dart';
import 'package:astro_journal/data/repositories/catalog_repository.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/shooting_record_repository.dart';
import 'package:astro_journal/features/catalog/view/catalog_screen.dart';
import 'package:astro_journal/features/catalog/viewmodel/catalog_view_model.dart';
import 'package:astro_journal/features/gallery/view/gallery_detail_screen.dart';
import 'package:astro_journal/features/gallery/view/gallery_screen.dart';
import 'package:astro_journal/features/gallery/viewmodel/gallery_view_model.dart';
import 'package:astro_journal/features/season/view/season_planner_screen.dart';
import 'package:astro_journal/features/season/viewmodel/season_planner_view_model.dart';
import 'package:astro_journal/features/sky_map/viewmodel/sky_map_view_model.dart';
import 'package:astro_journal/features/sky_map/widgets/sky_map_filter_sheet.dart';
import 'package:astro_journal/services/catalog_search_service.dart';
import 'package:astro_journal/services/catalog_favorite_controller.dart';
import 'package:astro_journal/services/equipment/equipment_recommendation_service.dart';
import 'package:astro_journal/services/mobile_display_scope_preferences.dart';
import 'package:astro_journal/services/photo_overlay_service.dart';
import 'package:astro_journal/services/season_planner_filter_service.dart';
import 'package:astro_journal/shared/widgets/catalog_object_card.dart';
import 'package:astro_journal/shared/widgets/catalog_object_image.dart';
import 'package:astro_journal/shared/widgets/app_file_image.dart';
import 'package:astro_journal/shared/widgets/inline_catalog_search_results.dart';
import 'package:astro_journal/shared/widgets/mobile_content_layout.dart';
import 'package:astro_journal/shared/widgets/mobile_photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_catalog_favorites.dart';

const _target = CatalogObject(
  id: 'NGC9999',
  number: 9999,
  catalog: CatalogType.ngc,
  name: '테스트용 이름이 긴 은하 대상',
  type: '은하',
  constellation: '긴 별자리 이름',
  ra: '12h',
  dec: '+33°',
  magnitude: '-',
);

const _famous = CatalogObject(
  id: 'M31',
  number: 31,
  catalog: CatalogType.messier,
  name: '안드로메다 은하',
  type: '은하',
  constellation: '-',
  ra: '00h',
  dec: '+41°',
  magnitude: '-',
);

class _Catalog extends Fake implements CatalogRepository {
  @override
  Future<List<CatalogObject>> getAll({bool listOnly = true}) async => [
    _famous,
    _target,
  ];
}

class _Records extends Fake implements ShootingRecordRepository {
  _Records([this.records = const []]);

  final List<ShootingRecord> records;

  @override
  Future<List<ShootingRecord>> getAll() async => records;
}

class _Equipment extends Fake implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => [];
}

class _SeasonFilter extends Fake implements SeasonPlannerFilterService {
  @override
  Future<void> save(Set<CatalogType> catalogFilters) async {}
}

class _Planner extends SeasonPlannerViewModel {
  _Planner(SeasonPlannerViewMode mode)
    : super(
        _Catalog(),
        _Records(),
        _SeasonFilter(),
        initialViewMode: mode,
        initialMonth: 1,
      );

  @override
  List<SeasonPlannerItem> get items => [
    const SeasonPlannerItem(object: _target, score: 80, peakMonth: 4),
  ];
}

CatalogFavoriteController _favorites(CatalogRepository repo) {
  final favorites = CatalogFavoriteController(
    remoteApi: FakeCatalogFavoritesRemote(['M31']),
    cache: FakeCatalogFavoritesCache(['M31']),
    catalogRepository: repo,
  );
  addTearDown(favorites.dispose);
  return favorites;
}

CatalogViewModel _catalogVm({bool mobile = false}) {
  final repo = _Catalog();
  final favorites = _favorites(repo);
  unawaited(favorites.restoreCache());
  return CatalogViewModel(
    repo,
    _Records(),
    _Equipment(),
    const EquipmentRecommendationService(),
    catalogFavorites: favorites,
    displayPreferences: mobile ? const MobileDisplayScopePreferences() : null,
  );
}

void _viewport(WidgetTester tester, double width, double height) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SliverGridDelegateWithFixedCrossAxisCount _grid(WidgetTester tester) =>
    tester.widget<GridView>(find.byType(GridView)).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;

Finder _chip(String label) => find.widgetWithText(FilterChip, label);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'catalog opens all in an image grid and restores a mobile choice',
    (tester) async {
      _viewport(tester, 320, 680);
      final vm = _catalogVm(mobile: true);
      await vm.load(deferHeavyWork: true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => vm),
            ChangeNotifierProvider(create: (_) => AppNavigationNotifier()),
          ],
          child: const MaterialApp(home: CatalogScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_grid(tester).crossAxisCount, 2);
      expect(_grid(tester).crossAxisSpacing, 5);
      expect(vm.displayScope, CatalogDisplayScope.all);
      expect(
        await const MobileDisplayScopePreferences().read(
          MobileDisplayScreen.catalog,
        ),
        isNull,
      );
      expect(
        vm.objects.map((object) => object.id),
        unorderedEquals(['M31', 'NGC9999']),
      );
      final targetTile = find.byKey(
        const ValueKey('mobile-catalog-tile-NGC9999'),
      );
      final targetImage = find.descendant(
        of: targetTile,
        matching: find.byType(CatalogObjectImage),
      );
      expect(targetImage, findsOneWidget);
      expect(
        tester.getBottomRight(targetImage).dy,
        lessThan(tester.getBottomRight(targetTile).dy),
      );
      expect(tester.getSize(targetTile).height, lessThan(176));
      expect(
        Theme.of(tester.element(targetTile)).cardTheme.color,
        PcDesign.card,
      );
      expect(_chip('은하'), findsOneWidget);
      expect(
        tester.getTopLeft(_chip('전체')).dy,
        lessThan(tester.getTopLeft(_chip('기타')).dy),
      );
      await tester.tap(find.text('유명천체'));
      await tester.pumpAndSettle();
      expect(vm.objects.map((object) => object.id), ['M31']);
      await tester.tap(_chip('은하'));
      await tester.pumpAndSettle();
      expect(vm.kindFilter, CatalogKindFilter.galaxy);
      await tester.tap(find.byTooltip('정렬'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름순'));
      await tester.pumpAndSettle();
      expect(vm.sortOrder, CatalogSortOrder.nameAsc);

      tester.view.physicalSize = const Size(400, 680);
      await tester.pumpAndSettle();
      expect(_grid(tester).crossAxisCount, 3);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await (await SharedPreferences.getInstance()).reload();
      final restarted = _catalogVm(mobile: true);
      await restarted.load(deferHeavyWork: true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => restarted),
            ChangeNotifierProvider(create: (_) => AppNavigationNotifier()),
          ],
          child: const MaterialApp(home: CatalogScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(restarted.displayScope, CatalogDisplayScope.famous);
      expect(find.byType(MobilePhotoTile), findsOneWidget);
      await tester.tap(find.text('전체보기'));
      await tester.pumpAndSettle();
      expect(restarted.displayScope, CatalogDisplayScope.all);
      expect(find.byType(MobilePhotoTile), findsNWidgets(2));

      tester.view.physicalSize = const Size(320, 680);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(_grid(tester).crossAxisCount, 1);
      expect(find.byType(MobilePhotoTile).hitTestable(), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog search stays usable in a short keyboard viewport', (
    tester,
  ) async {
    _viewport(tester, 320, 640);
    final vm = _catalogVm(mobile: true);
    await vm.load(deferHeavyWork: true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => vm),
          ChangeNotifierProvider(create: (_) => AppNavigationNotifier()),
        ],
        child: const MaterialApp(home: CatalogScreen()),
      ),
    );
    await tester.tap(find.text('유명천체'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('천체 검색'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'NGC9999');
    await tester.pumpAndSettle();
    final results = find.byType(InlineCatalogSearchResults);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: results, matching: find.byType(ListTile)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('검색 닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery photo grid, date view, sorting and filters still work', (
    tester,
  ) async {
    _viewport(tester, 360, 640);
    final date = DateTime(2026, 7, 8);
    final vm = GalleryViewModel(
      _Records([
        for (final id in ['1', '2'])
          ShootingRecord(
            id: id,
            celestialObjectId: _target.id,
            capturedAt: date,
            createdAt: date,
            photoUri: 'missing-test-$id.jpg',
            location: '집',
          ),
      ]),
      _Catalog(),
      CatalogSearchService(),
    );
    await vm.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => vm),
          Provider(create: (_) => PhotoOverlayService(_Catalog())),
        ],
        child: const MaterialApp(home: GalleryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(_grid(tester).crossAxisCount, 2);
    expect(_grid(tester).crossAxisSpacing, 5);
    final photo = find.byType(AppFileImage);
    final photoTile = find.byType(MobilePhotoTile);
    expect(tester.widget<AppFileImage>(photo).fit, BoxFit.cover);
    expect(tester.getSize(photo).width, greaterThan(160));
    expect(tester.getSize(photo).height, greaterThan(145));
    expect(
      tester.getSize(photo).height / tester.getSize(photoTile).height,
      greaterThan(.8),
    );
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(_grid(tester).crossAxisCount, 1);
    expect(tester.getSize(photo).width, greaterThan(288));
    tester.view.physicalSize = const Size(820, 720);
    await tester.pumpAndSettle();
    expect(_grid(tester).crossAxisCount, 4);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    await tester.tap(photoTile);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryDetailScreen), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final count = tester.widget<Text>(find.text('2'));
    expect(count.style?.color, PcDesign.background);
    await tester.tap(_chip('은하'));
    await tester.pumpAndSettle();
    expect(vm.categoryFilter, GalleryObjectCategory.galaxy);
    await tester.tap(find.byTooltip('정렬'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오래된 촬영순'));
    await tester.pumpAndSettle();
    expect(vm.sortOrder, GallerySortOrder.oldestFirst);
    await tester.tap(find.text('날짜별'));
    await tester.pumpAndSettle();
    expect(vm.viewMode, GalleryViewMode.byDate);
    expect(find.textContaining('2026.07.08'), findsOneWidget);

    tester.view.physicalSize = const Size(320, 400);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('필터'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('장소'));
    await tester.pumpAndSettle();
    final place = find.widgetWithText(ListTile, '집');
    await tester.ensureVisible(place);
    await tester.tap(place);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(vm.filterLocation, '집');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile sky scope restores independently and keeps positions', (
    tester,
  ) async {
    _viewport(tester, 360, 720);
    const preferences = MobileDisplayScopePreferences();
    await preferences.write(MobileDisplayScreen.catalog, true);
    final repo = _Catalog();
    final favorites = _favorites(repo);
    await favorites.restoreCache();
    SkyMapViewModel newSky({bool mobile = true}) {
      final map = SkyMapViewModel(
        repo,
        _Equipment(),
        null,
        () => DateTime(2026, 11, 19, 21),
        favorites,
        mobile ? preferences : null,
      );
      addTearDown(map.dispose);
      return map;
    }

    final sky = newSky();
    await tester.runAsync(sky.load);
    expect(sky.filters.famousOnly, isTrue);
    expect(await preferences.read(MobileDisplayScreen.skyMap), isNull);
    sky.toggleCatalog(CatalogType.ngc);
    sky.updateCanvasSize(const Size(360, 600));
    sky.selectObject(_famous);
    final before = sky.visibleObjects.singleWhere((o) => o.catalogId == 'M31');
    expect(sky.searchResults(_target.displayName), isEmpty);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showSkyMapFilterSheet(context: context, viewModel: sky),
              child: const Text('성도 필터'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('성도 필터'));
    await tester.pumpAndSettle();
    final scope = find.byKey(const ValueKey('sky-map-famous-mode'));
    expect(tester.widget<SegmentedButton<bool>>(scope).selected, {true});
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(scope).selected, {false});
    expect(
      sky.searchResults(_target.displayName).map((result) => result.id),
      contains(_target.id),
    );
    final after = sky.visibleObjects.singleWhere((o) => o.catalogId == 'M31');
    expect(
      Offset(after.screenX, after.screenY),
      Offset(before.screenX, before.screenY),
    );

    await (await SharedPreferences.getInstance()).reload();
    final reopened = newSky();
    await tester.runAsync(reopened.load);
    expect(reopened.filters.famousOnly, isFalse);
    expect(await preferences.read(MobileDisplayScreen.catalog), isTrue);
    final desktop = newSky(mobile: false);
    expect(desktop.filters.famousOnly, isFalse);
    desktop.setFamousOnly(true);
    await tester.pumpAndSettle();
    expect(await preferences.read(MobileDisplayScreen.skyMap), isFalse);

    await tester.tap(find.text('유명천체'));
    await tester.pumpAndSettle();
    sky.focusObjectLocation(_target);
    expect(sky.filters.famousOnly, isFalse);
    sky.restorePreferredDisplayScope();
    await tester.pumpAndSettle();
    expect(sky.filters.famousOnly, isTrue);
    expect(await preferences.read(MobileDisplayScreen.skyMap), isTrue);
    final freshDesktop = newSky(mobile: false);
    await tester.runAsync(freshDesktop.load);
    expect(freshDesktop.filters.famousOnly, isFalse);
  });

  testWidgets('planner wraps months and seasons while keeping selection', (
    tester,
  ) async {
    _viewport(tester, 320, 540);
    final planner = _Planner(SeasonPlannerViewMode.byMonth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SeasonPlannerViewModel>(
            create: (_) => planner,
          ),
          ChangeNotifierProvider(create: (_) => _catalogVm()),
        ],
        child: const MaterialApp(home: SeasonPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('월별 계획'), findsOneWidget);
    expect(
      tester.getTopLeft(_chip('1월')).dy,
      lessThan(tester.getTopLeft(_chip('12월')).dy),
    );
    await tester.ensureVisible(_chip('12월'));
    await tester.tap(_chip('12월'));
    await tester.pumpAndSettle();
    expect(planner.selectedMonth, 12);
    await tester.ensureVisible(find.text('계절별'));
    await tester.tap(find.text('계절별'));
    await tester.pumpAndSettle();
    expect(find.text('계절별 촬영 대상'), findsOneWidget);
    final summer = _chip('여름 6~8월');
    await tester.ensureVisible(summer);
    await tester.tap(summer);
    await tester.pumpAndSettle();
    expect(planner.selectedSeason.label, '여름');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop still uses its own layout and surrounding theme stays put',
    (tester) async {
      _viewport(tester, 1700, 900);
      await const MobileDisplayScopePreferences().write(
        MobileDisplayScreen.catalog,
        false,
      );
      final vm = _catalogVm();
      await vm.load(deferHeavyWork: true);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => vm),
            ChangeNotifierProvider(create: (_) => AppNavigationNotifier()),
          ],
          child: MaterialApp(
            theme: AppTheme.pcDark,
            home: const CatalogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileContentLayout), findsNothing);
      expect(_grid(tester).crossAxisCount, 8);
      expect(_grid(tester).crossAxisSpacing, 12);
      expect(vm.objects.map((object) => object.id), ['M31']);
      expect(
        PcDesign.isActive(tester.element(find.byType(CatalogObjectCard))),
        isTrue,
      );
      await tester.tap(find.text('전체보기'));
      await tester.pumpAndSettle();
      expect(
        vm.objects.map((object) => object.id),
        unorderedEquals(['M31', 'NGC9999']),
      );
      await tester.tap(find.text('유명천체'));
      await tester.pumpAndSettle();
      expect(
        await const MobileDisplayScopePreferences().read(
          MobileDisplayScreen.catalog,
        ),
        isFalse,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              expect(PcDesign.isStyled(context), isFalse);
              return MobileContentTheme(
                builder: (localContext) {
                  expect(PcDesign.isMobileContent(localContext), isTrue);
                  expect(PcDesign.isActive(localContext), isFalse);
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop gallery and both planner modes retain grid rules', (
    tester,
  ) async {
    _viewport(tester, 1700, 900);
    final date = DateTime(2026, 7, 8);
    final gallery = GalleryViewModel(
      _Records([
        ShootingRecord(
          id: 'desktop-photo',
          celestialObjectId: _target.id,
          capturedAt: date,
          createdAt: date,
          photoUri: 'missing-desktop-test.jpg',
        ),
      ]),
      _Catalog(),
      CatalogSearchService(),
    );
    await gallery.load();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => gallery,
        child: MaterialApp(
          theme: AppTheme.pcDark,
          home: const GalleryScreen(showHomeNavigation: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MobileContentLayout), findsNothing);
    expect(_grid(tester).crossAxisCount, 8);
    expect(_grid(tester).crossAxisSpacing, 6);
    expect(_grid(tester).childAspectRatio, 0.85);

    for (final mode in SeasonPlannerViewMode.values) {
      await tester.pumpWidget(
        MultiProvider(
          key: ValueKey(mode),
          providers: [
            ChangeNotifierProvider<SeasonPlannerViewModel>(
              create: (_) => _Planner(mode),
            ),
            ChangeNotifierProvider(create: (_) => _catalogVm()),
          ],
          child: MaterialApp(
            theme: AppTheme.pcDark,
            home: const SeasonPlannerScreen(fixedViewMode: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileContentLayout), findsNothing);
      expect(_grid(tester).crossAxisCount, 8);
      expect(_grid(tester).crossAxisSpacing, 12);
      expect(_grid(tester).childAspectRatio, 1.1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow planner keeps controls reachable with larger text', (
    tester,
  ) async {
    _viewport(tester, 320, 520);
    final planner = _Planner(SeasonPlannerViewMode.byMonth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SeasonPlannerViewModel>(
            create: (_) => planner,
          ),
          ChangeNotifierProvider(create: (_) => _catalogVm()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const SeasonPlannerScreen(fixedViewMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_grid(tester).crossAxisCount, 1);
    await tester.ensureVisible(find.text('전체보기'));
    await tester.tap(find.text('전체보기'));
    await tester.pumpAndSettle();
    expect(planner.displayScope, CatalogDisplayScope.all);
    await tester.ensureVisible(_chip('미촬영만'));
    await tester.tap(_chip('미촬영만'));
    await tester.pumpAndSettle();
    expect(planner.uncapturedOnly, isTrue);
    await tester.ensureVisible(_chip('12월'));
    await tester.tap(_chip('12월'));
    await tester.pumpAndSettle();
    expect(planner.selectedMonth, 12);
    expect(tester.takeException(), isNull);
  });
}
