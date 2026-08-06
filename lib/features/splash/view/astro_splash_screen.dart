import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/splash_image_service.dart';
import '../models/splash_progress_state.dart';
import '../models/startup_step.dart';
import '../viewmodel/app_startup_view_model.dart';

/// AstroJournal 브랜드 Splash.
///
/// ```
/// AstroSplashScreen
/// ├── VisualLayer   (~75%, 생성 1회 — Progress와 무관)
/// └── LoadingLayer  (~25%, 상태/Progress만 갱신)
/// ```
class AstroSplashScreen extends StatefulWidget {
  const AstroSplashScreen({
    super.key,
    this.startup,
    this.progress,
    this.splashImageService,
    this.steps = const [],
    this.tagline = '밤하늘을 준비하고 있습니다.',
    this.errorMessage,
  });

  final AppStartupViewModel? startup;
  final ValueListenable<SplashProgressState>? progress;
  final SplashImageService? splashImageService;
  final List<StartupStep> steps;
  final String tagline;
  final String? errorMessage;

  @override
  State<AstroSplashScreen> createState() => _AstroSplashScreenState();
}

class _AstroSplashScreenState extends State<AstroSplashScreen> {
  /// Progress 갱신 시 Element 재사용 → VisualLayer rebuild 방지.
  late final Widget _visualLayer = VisualLayer(
    key: const ValueKey<String>('splash_visual_layer'),
    splashImageService: widget.splashImageService,
  );

  late final Widget _loadingLayer = LoadingLayer(
    key: const ValueKey<String>('splash_loading_layer'),
    startup: widget.startup,
    progress: widget.progress,
    steps: widget.steps,
    tagline: widget.tagline,
    errorMessage: widget.errorMessage,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050814),
      body: Column(
        children: [
          Expanded(flex: 75, child: _visualLayer),
          Expanded(flex: 25, child: _loadingLayer),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// VisualLayer — 단 한 번 구성, Progress와 분리
// ──────────────────────────────────────────────

class VisualLayer extends StatefulWidget {
  const VisualLayer({
    super.key,
    this.splashImageService,
  });

  final SplashImageService? splashImageService;

  @override
  State<VisualLayer> createState() => _VisualLayerState();
}

class _VisualLayerState extends State<VisualLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  late final SplashImageService _service;

  File? _imageFile;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _service = widget.splashImageService ?? SplashImageService();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadImage();
  }

  Future<void> _loadImage() async {
    final pick = await _service.pickForDisplay();
    if (!mounted) return;
    setState(() {
      _imageFile = pick.file;
      _ready = true;
    });
    await _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF050814),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경(이미지 또는 폴백) — fade in
            FadeTransition(
              opacity: _fade,
              child: _ready
                  ? (_imageFile != null
                      ? _SplashPhoto(file: _imageFile!)
                      : const _FallbackSky())
                  : const ColoredBox(color: Color(0xFF050814)),
            ),
            // 하단 가독성용 그라데이션
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x66050814),
                      Color(0xE6050814),
                    ],
                    stops: [0.45, 0.72, 1.0],
                  ),
                ),
              ),
            ),
            // 은은한 별 반짝임 (2~3개)
            const IgnorePointer(child: _TwinkleStars()),
            // 브랜드
            SafeArea(
              bottom: false,
              child: FadeTransition(
                opacity: _fade,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BrandLogo(),
                        const SizedBox(height: 12),
                        const Text(
                          'AstroJournal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            shadows: [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Capture the Night Sky',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13,
                            letterSpacing: 0.4,
                            shadows: const [
                              Shadow(
                                color: Color(0x88000000),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashPhoto extends StatelessWidget {
  const _SplashPhoto({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    // BoxFit.contain — 잘림 없이 화면에 맞춤 (여백은 어두운 배경)
    return ColoredBox(
      color: const Color(0xFF050814),
      child: Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const _FallbackSky(),
      ),
    );
  }
}

class _FallbackSky extends StatelessWidget {
  const _FallbackSky();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050814),
            Color(0xFF0B1633),
            Color(0xFF132447),
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.28),
        border: Border.all(
          color: AppColors.solar.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.solar.withValues(alpha: 0.25),
            blurRadius: 18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/icon/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(
          Icons.auto_awesome,
          color: AppColors.solar,
          size: 30,
        ),
      ),
    );
  }
}

/// 별 2~3개의 느린 반짝임 (짧은 Splash용 최소 모션).
class _TwinkleStars extends StatefulWidget {
  const _TwinkleStars();

  @override
  State<_TwinkleStars> createState() => _TwinkleStarsState();
}

class _TwinkleStarsState extends State<_TwinkleStars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return CustomPaint(
          painter: _TwinklePainter(t),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _TwinklePainter extends CustomPainter {
  _TwinklePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final stars = <(double, double, double)>[
      (0.18, 0.16, 1.6),
      (0.78, 0.22, 1.3),
      (0.62, 0.12, 1.1),
    ];
    for (var i = 0; i < stars.length; i++) {
      final (nx, ny, r) = stars[i];
      final phase = (t + i * 0.33) % 1.0;
      final alpha = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(size.width * nx, size.height * ny),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter oldDelegate) =>
      oldDelegate.t != t;
}

// ──────────────────────────────────────────────
// LoadingLayer — Progress / 상태만 반응
// ──────────────────────────────────────────────

class LoadingLayer extends StatelessWidget {
  const LoadingLayer({
    super.key,
    this.startup,
    this.progress,
    this.steps = const [],
    this.tagline = '밤하늘을 준비하고 있습니다.',
    this.errorMessage,
  });

  final AppStartupViewModel? startup;
  final ValueListenable<SplashProgressState>? progress;
  final List<StartupStep> steps;
  final String tagline;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF050814),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              4,
              AppTheme.spacingLg,
              AppTheme.spacingMd,
            ),
            child: _buildListener(),
          ),
        ),
      ),
    );
  }

  Widget _buildListener() {
    if (startup != null) {
      return ListenableBuilder(
        listenable: startup!,
        builder: (context, _) => _StatusBody(
          steps: startup!.steps,
          tagline: startup!.tagline,
          errorMessage: startup!.errorMessage,
        ),
      );
    }
    if (progress != null) {
      return ValueListenableBuilder<SplashProgressState>(
        valueListenable: progress!,
        builder: (context, state, _) => _StatusBody(
          steps: state.steps,
          tagline: state.tagline,
          errorMessage: state.errorMessage,
        ),
      );
    }
    return _StatusBody(
      steps: steps,
      tagline: tagline,
      errorMessage: errorMessage,
    );
  }
}

/// 하위 호환 별칭.
typedef LoadingStatusLayer = LoadingLayer;
typedef ProgressArea = LoadingLayer;
typedef AstronomyVisualLayer = VisualLayer;

class _StatusBody extends StatelessWidget {
  const _StatusBody({
    required this.steps,
    required this.tagline,
    this.errorMessage,
  });

  final List<StartupStep> steps;
  final String tagline;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                tagline,
                key: ValueKey(tagline),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        if (errorMessage != null) ...[
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.red.shade300,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in steps)
                    SizedBox(
                      height: 22,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          step.displayLabel,
                          style: TextStyle(
                            color: switch (step.status) {
                              StartupStepStatus.done => AppColors.messier,
                              StartupStepStatus.loading => AppColors.solar,
                              StartupStepStatus.error => Colors.red.shade300,
                              StartupStepStatus.pending =>
                                AppColors.textSecondary.withValues(alpha: 0.45),
                            },
                            fontSize: 12,
                            fontWeight: step.status == StartupStepStatus.loading
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: AppColors.textSecondary.withValues(alpha: 0.2),
            color: AppColors.solar,
          ),
        ),
      ],
    );
  }
}
