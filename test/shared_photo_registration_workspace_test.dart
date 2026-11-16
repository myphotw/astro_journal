import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_capture_capability.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/photo_metadata.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/desktop/view/pc_photo_registration_screen.dart';
import 'package:astro_journal/features/photo_first/models/registration_session.dart';
import 'package:astro_journal/features/photo_first/viewmodel/photo_first_registration_view_model.dart';
import 'package:astro_journal/services/photo_registration_service.dart';
import 'package:astro_journal/shared/widgets/integration_minutes_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _object = CatalogObject(
  id: 'M42',
  number: 42,
  catalog: CatalogType.messier,
  name: '오리온 대성운',
  type: '성운',
  constellation: '오리온',
  ra: '-',
  dec: '-',
  magnitude: '-',
);

class _Equipment extends Fake implements EquipmentRepository {
  _Equipment([this.items = const []]);

  final List<Equipment> items;

  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => items;
}

class _Sites extends Fake implements ObservationSiteRepository {
  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async => [];
}

class _Photos extends ChangeNotifier
    implements PhotoFirstRegistrationViewModel {
  @override
  List<CatalogObject> get allObjects => const [_object];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'catalog entry retains the desktop queue, preview, and details columns',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final session = RegistrationSession(
        payload: PhotoRegistrationPayload(
          photoId: 'photo-1',
          localPath: 'missing-photo.jpg',
          originalFilename: 'missing-photo.jpg',
          exifInfo: ExifInfo(
            filename: 'missing-photo.jpg',
            size: '1',
            date: '',
            equipment: '',
            focal: '',
            fstop: '',
            exposure: '',
            iso: '',
            resolution: '',
          ),
          metadata: const PhotoMetadata(),
        ),
        selectedObject: _object,
      );
      addTearDown(session.disposeNotifiers);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<EquipmentRepository>.value(value: _Equipment()),
            Provider<ObservationSiteRepository>.value(value: _Sites()),
            ChangeNotifierProvider<PhotoFirstRegistrationViewModel>.value(
              value: _Photos(),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: PcPhotoRegistrationScreen(
              initialSessions: [session],
              initialObject: _object,
            ),
          ),
        ),
      );
      await tester.pump();

      final queueX = tester.getTopLeft(find.text('등록할 사진')).dx;
      final previewX = tester
          .getTopLeft(find.text('missing-photo.jpg').last)
          .dx;
      final detailsX = tester.getTopLeft(find.text('등록 정보')).dx;
      expect(queueX, lessThan(previewX));
      expect(previewX, lessThan(detailsX));
      expect(find.textContaining('오리온 대성운'), findsWidgets);
      expect(find.text('대상 검색'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(800, 960));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile keeps the same sections in a vertical workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = RegistrationSession(
      payload: PhotoRegistrationPayload(
        photoId: 'mobile-photo',
        localPath: 'missing-photo.jpg',
        originalFilename: 'missing-photo.jpg',
        exifInfo: ExifInfo(
          filename: 'missing-photo.jpg',
          size: '1',
          date: '',
          equipment: '',
          focal: '',
          fstop: '',
          exposure: '',
          iso: '',
          resolution: '',
        ),
        metadata: const PhotoMetadata(),
      ),
      selectedObject: _object,
    );
    addTearDown(session.disposeNotifiers);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<EquipmentRepository>.value(value: _Equipment()),
          Provider<ObservationSiteRepository>.value(value: _Sites()),
          ChangeNotifierProvider<PhotoFirstRegistrationViewModel>.value(
            value: _Photos(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: PcPhotoRegistrationScreen(
            initialSessions: [session],
            initialObject: _object,
          ),
        ),
      ),
    );
    await tester.pump();

    final queueY = tester.getTopLeft(find.text('등록할 사진')).dy;
    final previewY = tester.getTopLeft(find.text('missing-photo.jpg').last).dy;
    final detailsY = tester.getTopLeft(find.text('등록 정보')).dy;
    expect(queueY, lessThan(previewY));
    expect(previewY, lessThan(detailsY));
    expect(find.text('대상 검색'), findsOneWidget);
    expect(find.text('주소 검색 · 즐겨찾는 관측지 · 지도'), findsOneWidget);
    expect(find.text('등록 전 촬영 · 위치 · Plate Solve 요약'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equipment and filter menus float beside their fields', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const equipment = Equipment(
      id: 'equip-1',
      name: 'Draco',
      kind: EquipmentKind.smartTelescope,
      purpose: EquipmentPurpose.imaging,
      captureCapability: EquipmentCaptureCapability(
        filters: [
          EquipmentFilterCapability(
            id: 'filter-1',
            type: EquipmentFilterType.dualBand,
            name: '듀얼밴드',
          ),
        ],
      ),
    );
    final session = RegistrationSession(
      payload: PhotoRegistrationPayload(
        photoId: 'menu-photo',
        localPath: 'missing-photo.jpg',
        originalFilename: 'missing-photo.jpg',
        exifInfo: ExifInfo(
          filename: 'missing-photo.jpg',
          size: '1',
          date: '',
          equipment: '',
          focal: '',
          fstop: '',
          exposure: '',
          iso: '',
          resolution: '',
        ),
        metadata: const PhotoMetadata(),
      ),
      selectedObject: _object,
    );
    addTearDown(session.disposeNotifiers);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<EquipmentRepository>.value(
            value: _Equipment(const [equipment]),
          ),
          Provider<ObservationSiteRepository>.value(value: _Sites()),
          ChangeNotifierProvider<PhotoFirstRegistrationViewModel>.value(
            value: _Photos(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: PcPhotoRegistrationScreen(initialSessions: [session]),
        ),
      ),
    );
    await tester.pump();

    final equipmentField = find.byKey(
      const ValueKey('equipment-menu-photo-null'),
    );
    final locationY = tester.getTopLeft(find.text('관측 위치')).dy;
    await tester.tap(equipmentField);
    await tester.pump();
    final equipmentItem = find.widgetWithText(MenuItemButton, 'Draco');
    expect(equipmentItem, findsOneWidget);
    expect(tester.getTopLeft(find.text('관측 위치')).dy, locationY);
    final equipmentBottom = tester.getBottomLeft(equipmentField).dy;
    final equipmentMenuTop = tester.getTopLeft(find.byType(MenuItemButton).first).dy;
    expect(equipmentMenuTop, greaterThanOrEqualTo(equipmentBottom - 20));
    expect(equipmentMenuTop, lessThanOrEqualTo(equipmentBottom + 24));
    await tester.tap(equipmentItem);
    await tester.pump();
    expect(session.equipmentId, 'equip-1');
    expect(find.widgetWithText(MenuItemButton, 'Draco'), findsNothing);

    final filterField = find.byKey(const ValueKey('filter-menu-photo-equip-1'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(filterField, findsOneWidget);
    final focalY = tester.getTopLeft(find.text('초점거리')).dy;
    final integrationField = find.descendant(
      of: find.byType(IntegrationMinutesField),
      matching: find.byType(TextField),
    );
    final filterDecorator = find.descendant(
      of: filterField,
      matching: find.byType(InputDecorator),
    );
    expect(
      tester.getTopLeft(filterField).dy,
      closeTo(tester.getTopLeft(integrationField).dy, 1),
    );
    expect(
      tester.getSize(filterDecorator).height,
      closeTo(tester.getSize(integrationField).height, 4),
    );
    await tester.tap(filterField);
    await tester.pump();
    final filterItem = find.widgetWithText(MenuItemButton, '듀얼밴드');
    expect(filterItem, findsOneWidget);
    expect(tester.getTopLeft(find.text('초점거리')).dy, focalY);
    final menuRect = tester.getRect(filterItem);
    expect(menuRect.top, greaterThanOrEqualTo(0));
    expect(menuRect.bottom, lessThanOrEqualTo(960));
    await tester.tap(filterItem);
    await tester.pump();
    expect(session.filter, '듀얼밴드');
    expect(tester.takeException(), isNull);
  });
}
