import 'package:astro_journal/core/constants/equipment_kind.dart';
import 'package:astro_journal/core/constants/equipment_purpose.dart';
import 'package:astro_journal/data/models/equipment.dart';
import 'package:astro_journal/data/models/equipment_recommendation.dart';
import 'package:astro_journal/data/models/eyepiece.dart';
import 'package:astro_journal/data/models/fov_box.dart';
import 'package:astro_journal/shared/widgets/equipment_recommendation_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('imaging values share a compact horizontal Wrap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(recommendation: _recommendation),
        ),
      ),
    );

    final imagingWrap = find.ancestor(
      of: find.text('S30'),
      matching: find.byType(Wrap),
    );
    expect(imagingWrap, findsOneWidget);
    expect(
      find.descendant(of: imagingWrap, matching: find.text('★★★★☆')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: imagingWrap, matching: find.text('화면의 38%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: imagingWrap, matching: find.text('촬영 가능')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('📷 촬영')).dy,
      lessThan(tester.getTopLeft(find.text('👁 안시')).dy),
    );
  });

  testWidgets('visual section keeps one column per eyepiece', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(recommendation: _recommendation),
        ),
      ),
    );

    expect(find.text('👁 안시'), findsOneWidget);
    expect(find.text('20mm'), findsOneWidget);
    expect(find.text('6mm'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
  });
}

const _imaging = Equipment(
  id: 's30',
  name: 'S30',
  kind: EquipmentKind.smartTelescope,
  purpose: EquipmentPurpose.imaging,
);

const _visual = Equipment(
  id: 'visual',
  name: '굴절망원경',
  kind: EquipmentKind.refractor,
  purpose: EquipmentPurpose.visual,
);

const _eyepiece20 = Eyepiece(
  id: 'ep20',
  equipmentId: 'visual',
  name: '20mm',
  focalLengthMm: 20,
  afovDegrees: 60,
);

const _eyepiece6 = Eyepiece(
  id: 'ep6',
  equipmentId: 'visual',
  name: '6mm',
  focalLengthMm: 6,
  afovDegrees: 60,
);

const _recommendation = ObjectEquipmentRecommendation(
  imaging: [
    ImagingEquipmentRecommendation(
      equipment: _imaging,
      score: 80,
      starCount: 4,
      reason: '촬영 가능',
      screenFillPercent: 38,
      framingRecommendation: FramingRecommendation.good,
    ),
  ],
  visual: [
    VisualEquipmentRecommendation(
      equipment: _visual,
      eyepiece: _eyepiece20,
      score: 90,
      starCount: 5,
      reason: '전체 관측',
      isRecommended: true,
      screenFillPercent: 99,
    ),
    VisualEquipmentRecommendation(
      equipment: _visual,
      eyepiece: _eyepiece6,
      score: 60,
      starCount: 3,
      reason: '고배율',
      isRecommended: true,
      screenFillPercent: 30,
    ),
  ],
);
