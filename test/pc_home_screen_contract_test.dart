import 'dart:io';

import 'package:astro_journal/features/home/view/pc_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

RegExp _keyPattern(String key) => RegExp(
  "(?:const\\s+)?Key\\s*\\(\\s*'${RegExp.escape(key)}'\\s*,?\\s*\\)",
);

int _keyIndex(String source, String key) =>
    _keyPattern(key).firstMatch(source)?.start ?? -1;

void main() {
  test(
    'Windows PC shell starts with Home and preserves shared tab indexes',
    () {
      final source = _source('lib/shared/widgets/pc_main_shell.dart');
      final pagesStart = source.indexOf('late final _pages');
      final defaultHome = source.indexOf(
        'child: const PcHomeScreen()',
        pagesStart,
      );
      final defaultCatalog = source.indexOf(
        'child: const CatalogScreen()',
        pagesStart,
      );
      final menuStart = source.indexOf('static const _items');
      final home = source.indexOf("label: '홈'", menuStart);
      final photo = source.indexOf("label: '사진 등록'", menuStart);
      final catalog = source.indexOf("label: '천체 카탈로그'", menuStart);
      final settings = source.indexOf("label: '설정'", menuStart);

      expect(source, contains('child: const PcHomeScreen()'));
      expect(defaultHome, greaterThanOrEqualTo(0));
      expect(defaultHome, lessThan(defaultCatalog));
      expect(source, contains("(index: 0, label: '홈'"));
      expect(source, contains("(index: 6, label: '사진 등록'"));
      expect(source, contains("(index: 1, label: '천체 카탈로그'"));
      expect(source, contains("(index: 7, label: '설정'"));
      expect(home, lessThan(photo));
      expect(photo, lessThan(catalog));
      expect(catalog, lessThan(settings));
    },
  );

  test('mobile shell keeps HomeScreen as its first tab', () {
    final source = _source('lib/shared/widgets/main_shell.dart');
    final firstNavigator = source.indexOf('late final List<Widget>');
    final home = source.indexOf('child: const HomeScreen()', firstNavigator);
    final catalog = source.indexOf(
      'child: const CatalogScreen()',
      firstNavigator,
    );

    expect(home, greaterThanOrEqualTo(0));
    expect(home, lessThan(catalog));
  });

  test('PC weather table freezes axes and owns vertical wheel events', () {
    final source = _source('lib/features/home/view/pc_home_screen.dart');
    final horizontalScrollbar = _keyIndex(
      source,
      'pc-home-weather-horizontal-scrollbar',
    );
    final frozenTimeColumn = _keyIndex(
      source,
      'pc-home-weather-frozen-time-column',
    );
    final frozenTimeColumnEnd = source.indexOf('Expanded(', frozenTimeColumn);
    final verticalScrollbar = _keyIndex(
      source,
      'pc-home-weather-vertical-scrollbar',
    );
    final horizontalBody = _keyIndex(
      source,
      'pc-home-weather-horizontal-body',
    );

    expect(source, contains(_keyPattern('pc-home-weather-fixed-header')));
    expect(source, contains(_keyPattern('pc-home-weather-frozen-corner')));
    expect(
      source,
      contains(_keyPattern('pc-home-weather-frozen-time-column')),
    );
    expect(source, contains(_keyPattern('pc-home-weather-horizontal-header')));
    expect(source, contains(_keyPattern('pc-home-weather-horizontal-body')));
    expect(source, contains(_keyPattern('pc-home-weather-scroll-body')));
    expect(frozenTimeColumn, greaterThanOrEqualTo(0));
    expect(frozenTimeColumnEnd, greaterThan(frozenTimeColumn));
    final frozenTimeSource = source.substring(
      frozenTimeColumn,
      frozenTimeColumnEnd,
    );
    expect(frozenTimeSource, contains('scrollbars: false'));
    expect(frozenTimeSource, contains('controller: _timeVerticalController'));
    expect(frozenTimeSource, isNot(contains('Scrollbar(')));
    expect(source, contains('controller: _headerHorizontalController'));
    expect(source, contains('controller: _bodyHorizontalController'));
    expect(source, contains('controller: _timeVerticalController'));
    expect(source, contains('controller: _bodyVerticalController'));
    expect(source, contains('_syncHeaderToBody'));
    expect(source, contains('_syncBodyToHeader'));
    expect(source, contains('_syncBodyToTimeColumn'));
    expect(source, contains('pointerSignalResolver.register'));
    expect(source, contains('position.pointerScroll'));
    expect(source, contains('respond(allowPlatformDefault: false)'));
    expect(horizontalScrollbar, greaterThanOrEqualTo(0));
    expect(verticalScrollbar, greaterThan(horizontalScrollbar));
    expect(horizontalBody, greaterThan(verticalScrollbar));
    expect(
      source.substring(horizontalScrollbar, verticalScrollbar),
      contains('controller: _bodyHorizontalController'),
    );
    expect(
      source.substring(verticalScrollbar, horizontalBody),
      contains('controller: _bodyVerticalController'),
    );
    expect(
      RegExp(
        r'thumbVisibility: _scrollbarsVisible',
      ).allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      RegExp(r'interactive: true').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('_setScrollbarsVisible(true)'));
    expect(source, contains('_setScrollbarsVisible(false)'));
    expect(
      RegExp(r'thickness: 5').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('_handleBodyPointerDown'));
    expect(source, contains('_handleBodyPointerMove'));
    expect(source, contains('_handleBodyPointerEnd'));
    expect(source, contains('_dragThreshold'));
    expect(source, contains('_jumpBy(_bodyHorizontalController, delta.dx)'));
    expect(source, contains('_jumpBy(_bodyVerticalController, delta.dy)'));
    expect(source, contains('position.minScrollExtent'));
    expect(source, contains('position.maxScrollExtent'));
  });

  test('PC recommendation and schedule cards reuse CatalogObjectImage', () {
    final source = _source('lib/features/home/view/pc_home_screen.dart');

    expect(source, contains('class _PcRecommendationCard'));
    expect(source, contains('class _PcScheduleCard'));
    expect(
      RegExp(r'CatalogObjectImage\(').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('userPhotoPath: home.userPhotoFor(object)'));
    expect(source, contains('const AstronomyEventsSection()'));
    expect(source, contains('HomeObservationContextControls('));
    expect(source, contains('HomeRecommendationRefreshNotice('));
    expect(source, contains('HomeScheduleComputationStatus('));
    expect(source, contains("'관측지수 산정 근거'"));
    expect(source, contains('condition.statusPrimaryReason'));
    expect(source, contains('condition.qualityComponents'));
    expect(source, contains(_keyPattern('pc-home-weather-fixed-header')));
    expect(source, contains(_keyPattern('pc-home-weather-scroll-body')));
  });

  test('PC observation assessment keeps one evidence structure for all states', () {
    final source = _source('lib/features/home/view/pc_home_screen.dart');
    final assessmentStart = source.indexOf('class _PcObservationAssessment');
    final assessmentEnd = source.indexOf(
      'class _PcAssessmentRow',
      assessmentStart,
    );
    final assessment = source.substring(assessmentStart, assessmentEnd);
    final finalScore = _keyIndex(
      assessment,
      'pc-home-observation-final-score',
    );
    final verdict = _keyIndex(assessment, 'pc-home-observation-verdict');
    final scoreComponents = _keyIndex(
      assessment,
      'pc-home-observation-score-components',
    );
    final forecastValues = _keyIndex(
      assessment,
      'pc-home-observation-forecast-values',
    );

    expect(finalScore, greaterThanOrEqualTo(0));
    expect(verdict, greaterThan(finalScore));
    expect(scoreComponents, greaterThan(verdict));
    expect(forecastValues, greaterThan(scoreComponents));
    expect(assessment, contains("ObservationStatus.good => '관측 가능'"));
    expect(assessment, contains("ObservationStatus.limited => '주의'"));
    expect(
      assessment,
      contains("ObservationStatus.unavailable => '관측 불가'"),
    );
    expect(assessment, contains('condition.statusPrimaryReason'));
    expect(assessment, contains('condition.primaryInfeasibleReason'));
    expect(assessment, contains("'관측 불가 원인'"));
    expect(assessment, contains('condition.contributions.isNotEmpty'));
    expect(assessment, contains('condition.qualityComponents.isNotEmpty'));
    expect(assessment, contains('condition.hasTonightForecast'));
    expect(assessment, contains('condition.averageCloudCoverage'));
    expect(assessment, contains('condition.averageWindSpeed'));
    expect(assessment, contains('condition.averagePrecipitationPop'));
    expect(assessment, contains('condition.averageVisibilityMeters'));
    expect(assessment, isNot(contains('calculateContributions')));
  });

  testWidgets('PC Home exposes every dashboard region on a wide window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PcHomeDashboardView(
            contextControls: _section('context'),
            astronomyPanel: _section('astronomy'),
            hourlyWeatherPanel: _section('weather'),
            recommendationPanel: _section('recommendations'),
            schedulePanel: _section('schedule'),
            eventsFooter: _section('events'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pc-home-context-controls')), findsOneWidget);
    expect(find.byKey(const Key('pc-home-sticky-header')), findsOneWidget);
    expect(find.byKey(const Key('pc-home-astronomy-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('pc-home-hourly-weather-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pc-home-recommendations-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pc-home-schedule-panel')), findsOneWidget);
    expect(find.byKey(const Key('pc-home-astronomy-events')), findsOneWidget);
    expect(find.byKey(const Key('pc-home-layout-wide')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('pc-home-context-controls')),
        matching: find.byKey(const Key('pc-home-scroll-view')),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('pc-home-astronomy-panel')),
        matching: find.byKey(const Key('pc-home-scroll-view')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('PC Home stacks vertically without overflow on a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PcHomeDashboardView(
            contextControls: _section('context', height: 120),
            astronomyPanel: _section('astronomy', height: 240),
            hourlyWeatherPanel: _section('weather', height: 300),
            recommendationPanel: _section('recommendations', height: 360),
            schedulePanel: _section('schedule', height: 360),
            eventsFooter: _section('events', height: 180),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pc-home-layout-narrow')), findsOneWidget);
    expect(find.byKey(const Key('pc-home-scroll-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _section(String label, {double height = 80}) => SizedBox(
  height: height,
  child: ColoredBox(
    color: Colors.black12,
    child: Center(child: Text(label)),
  ),
);
