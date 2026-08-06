import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'app.dart';
import 'core/database/sqflite_bootstrap.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'data/repositories/bortle_repository_impl.dart';
import 'features/splash/models/splash_progress_state.dart';
import 'features/splash/models/startup_step.dart';
import 'features/splash/splash_frame_yield.dart';
import 'features/splash/view/astro_splash_screen.dart';
import 'services/catalog_display_name_resolver.dart';
import 'services/catalog_import_service.dart';
import 'services/catalog_search_service.dart';
import 'services/location_service.dart';
import 'services/observation_condition_probe.dart';
import 'services/observation_condition_service.dart';

Future<void> _initGoogleMapsAndroid() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  final impl = GoogleMapsFlutterPlatform.instance;
  if (impl is! GoogleMapsFlutterAndroid) return;

  // Hybrid Composition: Flutter 오버레이(검색창 등) 터치가 지도 PlatformView에
  // 먹히지 않도록 한다. 최신 렌더러로 제스처 안정성도 개선한다.
  impl.useAndroidViewSurface = true;
  try {
    await impl.initializeWithRenderer(AndroidMapRenderer.latest);
  } catch (_) {
    // 이미 초기화된 경우 등 — 무시
  }
}

/// DB 마이그레이션 등 무거운 초기화가 끝날 때까지 로딩 UI를 표시한다.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Object? _error;
  StackTrace? _stackTrace;

  late final ValueNotifier<SplashProgressState> _progress;

  static const _initialSteps = <StartupStep>[
    StartupStep(id: 'maps', label: '지도 엔진'),
    StartupStep(id: 'database', label: '로컬 데이터베이스'),
    StartupStep(id: 'aliases', label: '검색 인덱스'),
    StartupStep(id: 'catalog_seed', label: '천체 카탈로그 시드'),
  ];

  @override
  void initState() {
    super.initState();
    _progress = ValueNotifier(
      const SplashProgressState(
        steps: _initialSteps,
        tagline: '밤하늘을 준비하고 있습니다.',
      ),
    );
    unawaited(_runInit());
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _setStep(
    String id,
    StartupStepStatus status, {
    String? tagline,
  }) async {
    final current = _progress.value;
    _progress.value = SplashProgressState(
      tagline: tagline ?? current.tagline,
      errorMessage: current.errorMessage,
      steps: [
        for (final step in current.steps)
          if (step.id == id) step.copyWith(status: status) else step,
      ],
    );
    // setState 없이 진행만 갱신 → 하늘 애니메이션 유지
    await yieldForSplashAnimation();
  }

  Future<void> _runInit() async {
    try {
      await _setStep(
        'maps',
        StartupStepStatus.loading,
        tagline: '지도 엔진을 준비하는 중...',
      );
      await _initGoogleMapsAndroid();
      await _setStep('maps', StartupStepStatus.done);

      await _setStep(
        'database',
        StartupStepStatus.loading,
        tagline: '로컬 데이터베이스를 여는 중...',
      );
      await AppDatabase.instance;
      await _setStep('database', StartupStepStatus.done);

      await _setStep(
        'aliases',
        StartupStepStatus.loading,
        tagline: '검색 인덱스를 준비하는 중...',
      );
      await Future.wait([
        CatalogSearchService.loadGlobalAliases(),
        CatalogDisplayNameResolver.load(),
      ]);
      await _setStep('aliases', StartupStepStatus.done);

      await _setStep(
        'catalog_seed',
        StartupStepStatus.loading,
        tagline: '천체 카탈로그를 불러오는 중...',
      );
      await CatalogImportService.importAllIfNeeded();
      await _setStep('catalog_seed', StartupStepStatus.done);

      if (kDebugMode) {
        unawaited(
          ObservationConditionProbe.run(
            ObservationConditionService(
              LocationService(),
              BortleRepositoryImpl(),
            ),
          ),
        );
      }

      if (!mounted) return;
      _progress.value = SplashProgressState(
        steps: _progress.value.steps,
        tagline: '화면 데이터를 준비하고 있습니다.',
      );
      await yieldForSplashAnimation();
      // ignore: use_build_context_synchronously — mounted 확인 후 호출
      runApp(const AstroJournalApp());
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stackTrace = stack;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '앱 초기화 실패',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                  Text(
                    '$_error',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (_stackTrace != null) ...[
                    const SizedBox(height: AppTheme.spacingMd),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          '$_stackTrace',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 단계 갱신은 ValueNotifier만 — MaterialApp/하늘 State는 재생성하지 않음
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: AstroSplashScreen(progress: _progress),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSqflite();
  runApp(const AppBootstrap());
}
