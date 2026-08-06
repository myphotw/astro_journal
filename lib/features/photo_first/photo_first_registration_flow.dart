import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/constants/analysis_status.dart';
import '../../core/constants/detect_method.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/plate_solve_result.dart';
import '../../services/catalog_search_service.dart';
import '../../services/photo_registration_service.dart';
import '../catalog/viewmodel/catalog_view_model.dart';
import '../gallery/viewmodel/gallery_view_model.dart';
import '../home/viewmodel/home_view_model.dart';
import '../stats/viewmodel/stats_view_model.dart';
import 'models/registration_session.dart';
import 'services/registration_image_cache.dart';
import 'view/registration_screen.dart';
import 'viewmodel/photo_first_registration_view_model.dart';

class _PendingRegistration {
  const _PendingRegistration({
    required this.object,
    required this.payload,
    required this.confirmed,
    required this.detectMethod,
    this.plateSolve,
  });

  final CatalogObject object;
  final PhotoRegistrationPayload payload;
  final ConfirmedMetadata confirmed;
  final DetectMethod? detectMethod;
  final PlateSolveResult? plateSolve;
}

/// GNB 사진 등록: 복사 직후 위저드 1회 push, EXIF는 백그라운드 enrich.
Future<void> runPhotoFirstRegistrationFlow(BuildContext context) async {
  final viewModel = context.read<PhotoFirstRegistrationViewModel>();
  final catalogVm = context.read<CatalogViewModel>();
  final registrationService = context.read<PhotoRegistrationService>();

  final stubs = await viewModel.pickPhotosCopyOnly(context);
  if (!context.mounted) return;

  if (stubs.isEmpty) {
    if (viewModel.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(viewModel.errorMessage!),
          duration: const Duration(milliseconds: 1800),
        ),
      );
    }
    return;
  }

  final existingIndex = catalogVm.searchIndex;
  if (existingIndex != null) {
    CatalogSearchService.adoptIndex(existingIndex, catalogVm.allObjects);
  } else {
    unawaited(catalogVm.finishDeferredHeavyWork());
  }

  // 사진 선택 완료 직후 중복 검사 (위저드 진입 전)
  final sessions = <RegistrationSession>[];
  for (final stub in stubs) {
    if (!context.mounted) return;
    final duplicate = await viewModel.checkDuplicateByFilename(stub);
    if (!context.mounted) return;
    if (duplicate != null) {
      final proceed = await _showDuplicateDialog(context, duplicate);
      if (!proceed) continue;
    }
    sessions.add(RegistrationSession(payload: stub));
  }

  if (sessions.isEmpty) {
    viewModel.reset();
    return;
  }

  for (final session in sessions) {
    unawaited(session.ensureThumbnailLoaded());
    unawaited(_enrichSession(
      session: session,
      viewModel: viewModel,
      registrationService: registrationService,
    ));
  }

  if (!context.mounted) return;
  final outcomes = await Navigator.of(context).push<List<RegistrationOutcome>>(
    PageRouteBuilder<List<RegistrationOutcome>>(
      pageBuilder: (context, animation, secondaryAnimation) {
        return RegistrationScreen(
          sessions: sessions,
          allObjects: viewModel.allObjects,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
    ),
  );

  if (!context.mounted) return;

  if (outcomes == null) {
    for (final s in sessions) {
      RegistrationImageCache.evict(s.localPath);
    }
    viewModel.reset();
    return;
  }

  final pending = <_PendingRegistration>[];
  for (final outcome in outcomes) {
    final object = outcome.session.selectedObject;
    if (object == null) continue;

    pending.add(
      _PendingRegistration(
        object: object,
        payload: outcome.session.payload,
        confirmed: outcome.confirmed,
        detectMethod: outcome.session.detectMethod,
        plateSolve: outcome.session.plateSolveResult,
      ),
    );
  }

  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final homeVm = context.read<HomeViewModel>();
  final galleryVm = context.read<GalleryViewModel>();
  final statsVm = context.read<StatsViewModel>();

  if (pending.isEmpty) {
    for (final s in sessions) {
      RegistrationImageCache.evict(s.localPath);
    }
    viewModel.reset();
    return;
  }

  final count = pending.length;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('사진 $count장이 등록되었습니다.'),
        duration: const Duration(milliseconds: 1400),
      ),
    );

  viewModel.beginBackgroundSave();
  unawaited(
    _persistRegistrationsInBackground(
      viewModel: viewModel,
      pending: pending,
      homeVm: homeVm,
      catalogVm: catalogVm,
      galleryVm: galleryVm,
      statsVm: statsVm,
      messenger: messenger,
    ),
  );
}

Future<void> _enrichSession({
  required RegistrationSession session,
  required PhotoFirstRegistrationViewModel viewModel,
  required PhotoRegistrationService registrationService,
}) async {
  try {
    final enriched = await registrationService.enrichPayload(session.payload);
    // 대상 확정 후 EXIF ready 알림 → 위저드가 대상검색 단계를 숨김
    if (session.selectedObject == null) {
      final resolved = viewModel.resolveTarget(enriched.exifInfo.targetName);
      if (resolved != null) {
        session.selectTarget(
          resolved,
          method: _detectMethodFromExifPayload(enriched),
        );
      }
    }
    session.applyEnrichedPayload(enriched);
  } catch (e) {
    session.markAnalysisFailed(e);
  }
}

Future<void> _persistRegistrationsInBackground({
  required PhotoFirstRegistrationViewModel viewModel,
  required List<_PendingRegistration> pending,
  required HomeViewModel homeVm,
  required CatalogViewModel catalogVm,
  required GalleryViewModel galleryVm,
  required StatsViewModel statsVm,
  required ScaffoldMessengerState messenger,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  await SchedulerBinding.instance.endOfFrame;

  String? lastError;

  try {
    for (final item in pending) {
      final record = await viewModel.registerPhoto(
        object: item.object,
        payload: item.payload,
        confirmed: item.confirmed,
        detectMethod: item.detectMethod,
        analysisStatus: AnalysisStatus.completed,
        plateSolve: item.plateSolve,
      );
      if (record != null) {
        RegistrationImageCache.evict(item.payload.localPath);
        catalogVm.applyCaptureFromRegistration(
          celestialObjectId: record.celestialObjectId,
          photoUri: record.photoUri ?? item.payload.localPath,
          capturedAt: record.capturedAt,
        );
      } else if (viewModel.errorMessage != null) {
        lastError = viewModel.errorMessage;
      }
      await Future<void>.delayed(Duration.zero);
      await SchedulerBinding.instance.endOfFrame;
    }
  } finally {
    viewModel.endBackgroundSave();
  }

  if (lastError != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(lastError),
          duration: const Duration(milliseconds: 2200),
        ),
      );
  }

  await Future<void>.delayed(const Duration(milliseconds: 120));
  await galleryVm.load(silent: true);

  unawaited(
    Future<void>.delayed(const Duration(seconds: 2), () async {
      await homeVm.load(deferHeavyWork: true);
      await homeVm.finishDeferredHeavyWork();
      await statsVm.load();
    }),
  );
}

DetectMethod _detectMethodFromExifPayload(PhotoRegistrationPayload payload) {
  final hasExifMetadata =
      payload.makerNoteMetadata != null || payload.ownerNameMetadata != null;
  if (!hasExifMetadata && payload.filenameMetadata != null) {
    return DetectMethod.filename;
  }
  return DetectMethod.exif;
}

Future<bool> _showDuplicateDialog(
  BuildContext context,
  DuplicateCheckResult duplicate,
) async {
  final message = duplicate.reason == DuplicateReason.sameFilename
      ? '동일한 파일명(${duplicate.existing.originalFilename ?? "알 수 없음"})의 촬영 기록이 이미 있습니다.'
      : '동일한 대상·촬영 시간의 기록이 이미 있습니다.';

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('중복 등록'),
      content: Text('$message\n\n중복 등록하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('등록 취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('중복 등록'),
        ),
      ],
    ),
  );
  return result ?? false;
}
