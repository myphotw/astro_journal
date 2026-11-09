import 'dart:typed_data';

import 'package:astro_journal/core/constants/catalog_type.dart';
import 'package:astro_journal/data/models/catalog_object.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/exif_info.dart';
import 'package:astro_journal/data/models/observation_site.dart';
import 'package:astro_journal/data/models/photo_metadata.dart';
import 'package:astro_journal/data/repositories/equipment_repository.dart';
import 'package:astro_journal/data/repositories/observation_site_repository.dart';
import 'package:astro_journal/features/photo_first/models/registration_session.dart';
import 'package:astro_journal/features/photo_first/view/registration_screen.dart';
import 'package:astro_journal/services/photo_registration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Equipment extends Fake implements EquipmentRepository {
  @override
  Future<List<Equipment>> getAll({bool activeOnly = false}) async => [];
}

class _Sites extends Fake implements ObservationSiteRepository {
  @override
  Future<List<ObservationSite>> list({bool includeDeleted = false}) async => [];
}

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

RegistrationSession _session(String id, {String exposure = ''}) {
  final session = RegistrationSession(
    payload: PhotoRegistrationPayload(
      photoId: id,
      localPath: '$id.jpg',
      originalFilename: '$id.jpg',
      exifInfo: ExifInfo(
        filename: '$id.jpg',
        size: '1',
        date: '',
        equipment: '',
        focal: '',
        fstop: '',
        exposure: exposure,
        iso: '',
        resolution: '',
      ),
      metadata: const PhotoMetadata(),
    ),
    selectedObject: _object,
  );
  // The registration test does not need to read a file from disk.
  session.thumbnailImage = MemoryImage(Uint8List(0));
  return session;
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _value(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _show(
  WidgetTester tester,
  List<RegistrationSession> sessions,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<EquipmentRepository>.value(value: _Equipment()),
        Provider<ObservationSiteRepository>.value(value: _Sites()),
      ],
      child: MaterialApp(
        home: RegistrationScreen(
          sessions: sessions,
          allObjects: const [_object],
          skipTargetStep: true,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('stack and exposure edit in either order updates saved seconds', (
    tester,
  ) async {
    final session = _session('first');
    await _show(tester, [session]);

    await tester.enterText(_field('스택수'), '100');
    await tester.enterText(_field('1장 노출시간'), '20');
    expect(_value(tester, '총 적분시간'), '33.333333');
    expect(session.toConfirmedMetadata().integrationSeconds, 2000);

    await tester.enterText(_field('스택수'), '120');
    expect(_value(tester, '총 적분시간'), '40');
    await tester.enterText(_field('1장 노출시간'), '0.5');
    expect(_value(tester, '총 적분시간'), '1');
    expect(session.toConfirmedMetadata().integrationSeconds, 60);
    await tester.enterText(_field('스택수'), '3');
    await tester.enterText(_field('1장 노출시간'), '1.25');
    expect(_value(tester, '총 적분시간'), '0.0625');
    expect(session.toConfirmedMetadata().integrationSeconds, 4);

    await tester.enterText(_field('스택수'), '');
    await tester.enterText(_field('1장 노출시간'), '60');
    await tester.enterText(_field('스택수'), '90');
    expect(_value(tester, '총 적분시간'), '90');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('manual and EXIF integration survive initial binding and edits', (
    tester,
  ) async {
    final session = _session('exif', exposure: '15분');
    await _show(tester, [session]);
    expect(_value(tester, '총 적분시간'), '15');

    await tester.enterText(_field('스택수'), '100');
    await tester.enterText(_field('1장 노출시간'), '20');
    expect(_value(tester, '총 적분시간'), '15');

    await tester.enterText(_field('총 적분시간'), '18');
    await tester.enterText(_field('스택수'), '120');
    expect(_value(tester, '총 적분시간'), '18');
    expect(session.toConfirmedMetadata().integrationSeconds, 1080);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('only an auto value clears on invalid input', (tester) async {
    final session = _session('invalid');
    await _show(tester, [session]);

    await tester.enterText(_field('1장 노출시간'), '30');
    await tester.enterText(_field('스택수'), '120');
    expect(_value(tester, '총 적분시간'), '60');
    await tester.enterText(_field('스택수'), '');
    expect(_value(tester, '총 적분시간'), '');
    expect(session.toConfirmedMetadata().integrationSeconds, isNull);

    await tester.enterText(_field('총 적분시간'), '25');
    await tester.enterText(_field('스택수'), 'bad');
    expect(_value(tester, '총 적분시간'), '25');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('registration sessions keep separate calculation ownership', (
    tester,
  ) async {
    final first = _session('one');
    final second = _session('two', exposure: '7분');
    await _show(tester, [first, second]);

    await tester.enterText(_field('스택수'), '120');
    await tester.enterText(_field('1장 노출시간'), '30');
    expect(_value(tester, '총 적분시간'), '60');

    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();
    await tester.tap(find.text('다음 사진'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_value(tester, '총 적분시간'), '7');
    expect(first.toConfirmedMetadata().integrationSeconds, 3600);
    expect(second.toConfirmedMetadata().integrationSeconds, 420);
  });
}
