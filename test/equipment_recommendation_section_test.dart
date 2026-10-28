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

    expect(
      find.byKey(const ValueKey('equipment-imaging-summary-s30')),
      findsOneWidget,
    );
    final imagingSummary = find.byKey(
      const ValueKey('equipment-imaging-summary-s30'),
    );
    expect(imagingSummary, findsOneWidget);
    expect(
      tester.widget<Container>(imagingSummary).decoration,
      isA<BoxDecoration>(),
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.text('S30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.textContaining('★')),
      findsNothing,
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.textContaining('☆')),
      findsNothing,
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.text('38%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.text('여유 있음')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: imagingSummary, matching: find.text('화각에 여유 있게 들어옴')),
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
    final visualTable = find.byType(Table);
    expect(visualTable, findsOneWidget);
    expect(
      find.descendant(of: visualTable, matching: find.text('평가')),
      findsNothing,
    );
    expect(
      find.descendant(of: visualTable, matching: find.textContaining('★')),
      findsNothing,
    );
    expect(find.text('화면'), findsOneWidget);
    expect(find.text('배율'), findsOneWidget);
    expect(find.text('비고'), findsOneWidget);
  });

  testWidgets('imaging summary wraps without overflow on a narrow screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: EquipmentRecommendationSection(
                recommendation: _recommendation,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('equipment-imaging-details-s30')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders AZ and EQ capture guidance without changing fit details',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EquipmentRecommendationSection(
                recommendation: _captureRecommendation,
              ),
            ),
          ),
        ),
      );

      final summary = find.byKey(
        const ValueKey('equipment-imaging-summary-s30'),
      );
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('38%')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('equipment-capture-mode-s30-alt_az')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('equipment-capture-mode-s30-equatorial')),
        findsOneWidget,
      );
      expect(find.text('AZ'), findsOneWidget);
      expect(find.text('EQ'), findsOneWidget);
      expect(find.text('20초'), findsOneWidget);
      expect(find.text('30초'), findsOneWidget);
      expect(find.text('5초'), findsOneWidget);
      expect(find.text('기본 촬영'), findsNWidgets(2));
      expect(find.text('밝은 영역 보호'), findsOneWidget);
      expect(find.text('희미한 구조'), findsOneWidget);
      expect(find.text('시험 촬영 시작값'), findsNWidgets(6));
      expect(find.textContaining('Bortle 9'), findsOneWidget);
      expect(find.textContaining('듀얼밴드'), findsNWidgets(2));
    },
  );

  testWidgets('stacks AZ and EQ capture guidance on a narrow screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: EquipmentRecommendationSection(
                  recommendation: _captureRecommendation,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final az = find.byKey(const ValueKey('equipment-capture-mode-s30-alt_az'));
    final eq = find.byKey(
      const ValueKey('equipment-capture-mode-s30-equatorial'),
    );
    expect(tester.getTopLeft(az).dy, lessThan(tester.getTopLeft(eq).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy equipment keeps fit result and shows setup hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(recommendation: _recommendation),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('equipment-capture-settings-empty-s30')),
      findsOneWidget,
    );
    expect(find.text('38%'), findsOneWidget);
  });

  testWidgets('imaging-only target does not render the visual section', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(
            recommendation: ObjectEquipmentRecommendation(
              imaging: [_imagingRecommendation],
              visual: [],
              showVisual: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('📷 촬영'), findsOneWidget);
    expect(find.text('👁 안시'), findsNothing);
    expect(find.text('등록된 안시 장비가 없습니다.'), findsNothing);
  });

  testWidgets('visual recommendation separates owned and ideal eyepieces', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(
            recommendation: ObjectEquipmentRecommendation(
              imaging: [],
              visual: [
                VisualEquipmentRecommendation(
                  equipment: _visualWithOptics,
                  eyepiece: _eyepiece20,
                  score: 90,
                  starCount: 5,
                  reason: '전체 관측',
                  isRecommended: true,
                  screenFillPercent: 60,
                  recommendedEyepieceFocalLengthMm: 12,
                ),
              ],
              showImaging: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('20mm'), findsOneWidget);
    expect(find.text('약 25배'), findsOneWidget);
    expect(find.text('권장 아이피스 약 12mm'), findsOneWidget);
  });

  testWidgets('visual telescope remains when no eyepiece is registered', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EquipmentRecommendationSection(
            recommendation: ObjectEquipmentRecommendation(
              imaging: [],
              visual: [
                VisualEquipmentRecommendation(
                  equipment: _visualWithOptics,
                  score: 70,
                  starCount: 4,
                  reason: '아이피스를 등록하면 바로 사용할 수 있습니다.',
                  isRecommended: true,
                  screenFillPercent: 80,
                  recommendedEyepieceFocalLengthMm: 12,
                ),
              ],
              showImaging: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('굴절망원경'), findsOneWidget);
    expect(find.text('권장 아이피스 약 12mm'), findsOneWidget);
    expect(find.text('등록된 안시 장비가 없습니다.'), findsNothing);
  });

  testWidgets(
    'imaging availability messages distinguish absence and metadata',
    (tester) async {
      Future<void> pump(
        EquipmentRecommendationAvailability availability,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EquipmentRecommendationSection(
                recommendation: ObjectEquipmentRecommendation(
                  imaging: const [],
                  visual: const [],
                  showVisual: false,
                  imagingAvailability: availability,
                ),
              ),
            ),
          ),
        );
      }

      await pump(EquipmentRecommendationAvailability.notRegistered);
      expect(find.text('등록된 촬영 장비가 없습니다.'), findsOneWidget);

      await pump(EquipmentRecommendationAvailability.insufficientData);
      expect(find.text('등록된 촬영 장비의 촬영 정보가 부족합니다.'), findsOneWidget);
    },
  );
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

const _visualWithOptics = Equipment(
  id: 'visual-optics',
  name: '굴절망원경',
  kind: EquipmentKind.refractor,
  purpose: EquipmentPurpose.visual,
  apertureMm: 90,
  focalLengthMm: 500,
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
      reason: '화각에 여유 있게 들어옴',
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

const _imagingRecommendation = ImagingEquipmentRecommendation(
  equipment: _imaging,
  score: 80,
  starCount: 4,
  reason: '화각에 여유 있게 들어옴',
  screenFillPercent: 38,
  framingRecommendation: FramingRecommendation.good,
);

const _captureRecommendation = ObjectEquipmentRecommendation(
  imaging: [
    ImagingEquipmentRecommendation(
      equipment: _imaging,
      score: 80,
      starCount: 4,
      reason: '화각에 여유 있게 들어옴',
      screenFillPercent: 38,
      framingRecommendation: FramingRecommendation.good,
      captureSettings: [
        CaptureModeRecommendation(
          modeId: 'alt_az',
          mode: CaptureRecommendationMode.altAz,
          label: 'AZ',
          recommendedExposureSeconds: 20,
          exposureSupportLabel: '지원: 2/5/10/20/30/60초',
          exposureConfidence: CaptureRecommendationConfidence.experimental,
          exposurePolicyId: 'capture.exposure.capability-relative.v1',
          exposureReason: '지원 범위 안에서 시험 촬영을 권장합니다.',
          exposureInputs: ['천체 발광성운', '모드 AZ'],
          exposureRecommendations: [
            CaptureExposureRecommendation(
              purpose: CaptureExposurePurpose.standard,
              exposureSeconds: 20,
              confidence: CaptureRecommendationConfidence.experimental,
              policyId: 'capture.exposure.purpose-aware.v2',
              reason: '기본 촬영 시작값',
            ),
            CaptureExposureRecommendation(
              purpose: CaptureExposurePurpose.highlightProtection,
              exposureSeconds: 5,
              confidence: CaptureRecommendationConfidence.experimental,
              policyId: 'capture.exposure.highlight-protection.v1',
              reason: 'HDR 보조 프레임',
            ),
            CaptureExposureRecommendation(
              purpose: CaptureExposurePurpose.faintStructure,
              confidence: CaptureRecommendationConfidence.experimental,
              policyId: 'capture.exposure.faint-structure-integration.v1',
              reason: '총 적산시간 확보',
              guidance: '기본 노출 유지 · 총 적산시간 확보',
            ),
          ],
          exposureAdvisories: ['관측지 집 · Bortle 9'],
          recommendedFilters: ['듀얼밴드'],
          supportedFilters: ['필터 끄기', '듀얼밴드'],
          filterReason: '발광성운 특성과 장비 지원 필터의 교집합',
          filterConfidence: CaptureRecommendationConfidence.experimental,
          filterPolicyId: 'capture.filter.target-semantics.v1',
          cautions: ['AZ 추적은 필드 회전 영향을 받을 수 있습니다.'],
        ),
        CaptureModeRecommendation(
          modeId: 'equatorial',
          mode: CaptureRecommendationMode.equatorial,
          label: 'EQ',
          recommendedExposureSeconds: 30,
          exposureSupportLabel: '지원: 2/5/10/20/30/60초',
          exposureConfidence: CaptureRecommendationConfidence.experimental,
          exposurePolicyId: 'capture.exposure.capability-relative.v1',
          exposureReason: '지원 범위 안에서 시험 촬영을 권장합니다.',
          exposureInputs: ['천체 발광성운', '모드 EQ'],
          recommendedFilters: ['듀얼밴드'],
          supportedFilters: ['필터 끄기', '듀얼밴드'],
          filterReason: '발광성운 특성과 장비 지원 필터의 교집합',
          filterConfidence: CaptureRecommendationConfidence.experimental,
          filterPolicyId: 'capture.filter.target-semantics.v1',
        ),
      ],
    ),
  ],
  visual: [],
  showVisual: false,
);
