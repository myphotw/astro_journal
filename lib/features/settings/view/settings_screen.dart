import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/home/viewmodel/home_view_model.dart';
import '../../../services/backup_service.dart';
import '../../../services/recommendation_settings_service.dart';
import '../viewmodel/equipment_view_model.dart';
import '../viewmodel/settings_view_model.dart';
import '../widgets/tc_backend_settings_section.dart';
import '../widgets/astrojournal_reset_section.dart';
import 'equipment_list_screen.dart';
import 'observation_site_list_screen.dart';
import 'recommendation_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SettingsViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (viewModel.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          _SectionHeader(title: '추천 대상 설정', icon: Icons.stars_outlined),
          _RecommendationSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: '관측지 관리', icon: Icons.location_on_outlined),
          _ObservationSiteSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: '장비 관리', icon: Icons.camera_alt_outlined),
          _EquipmentSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: '서비스 연결', icon: Icons.cloud_outlined),
          const TcBackendSettingsSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: '백업 / 가져오기', icon: Icons.backup_outlined),
          _BackupSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: '초기화', icon: Icons.delete_sweep_outlined),
          const AstroJournalResetSection(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Section Header
// ──────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.messier),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.messier,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Recommendation Section
// ──────────────────────────────────────────────

// ──────────────────────────────────────────────
// Equipment Section
// ──────────────────────────────────────────────

class _EquipmentSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.camera_alt_outlined,
          color: AppColors.textSecondary,
        ),
        title: const Text(
          '장비 등록·관리',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: const Text(
          '촬영·안시 장비 및 아이피스',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(
              value: context.read<EquipmentViewModel>(),
              child: const EquipmentListScreen(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ObservationSiteSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: ListTile(
        key: const Key('observation-site-settings-entry'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.location_on_outlined,
          color: AppColors.textSecondary,
        ),
        title: const Text(
          '관측지 관리',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: const Text(
          '저장된 관측지 목록',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ObservationSiteListScreen(),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Recommendation Section
// ──────────────────────────────────────────────

class _RecommendationSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.tune_outlined,
          color: AppColors.textSecondary,
        ),
        title: const Text(
          '추천 필터 설정',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: const Text(
          '카탈로그 · 추천 우선순위',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textSecondary,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MultiProvider(
              providers: [
                Provider.value(
                  value: context.read<RecommendationSettingsService>(),
                ),
                ChangeNotifierProvider.value(
                  value: context.read<HomeViewModel>(),
                ),
              ],
              child: const RecommendationSettingsScreen(),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// API Section
class _BackupSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<SettingsViewModel>();

    return _SettingsCard(
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.upload_outlined,
              color: AppColors.textSecondary,
            ),
            title: const Text(
              '백업 내보내기',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'DB와 사진을 ZIP으로 묶어 원하는 폴더에 저장합니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
            onTap: () => _exportBackup(context, viewModel),
          ),
          const Divider(color: AppColors.textSecondary, height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.download_outlined,
              color: AppColors.textSecondary,
            ),
            title: const Text(
              '백업 가져오기',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'ZIP 파일을 선택하여 복원합니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
            onTap: () => _importBackup(context, viewModel),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup(
    BuildContext context,
    SettingsViewModel viewModel,
  ) async {
    final progress = ValueNotifier(
      const BackupExportProgress(stage: 'preparing', message: '백업 준비 중…'),
    );
    // packing → choose: 같은 다이얼로그 안에서 전환 (닫았다 다시 열지 않음)
    final phase = ValueNotifier<_BackupDialogPhase>(_BackupDialogPhase.packing);
    final saveChoice = Completer<_BackupSaveAction>();

    // SettingsScreen context — 탭 context가 dispose돼도 루트 오버레이는 유지
    final dialogContext = Navigator.of(context, rootNavigator: true).context;

    unawaited(
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => PopScope(
          canPop: false,
          child: ValueListenableBuilder<_BackupDialogPhase>(
            valueListenable: phase,
            builder: (context, current, _) {
              if (current == _BackupDialogPhase.packing) {
                return AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: const Text(
                    '백업 내보내기',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  content: _BackupProgressBody(progress: progress),
                );
              }
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text(
                  '압축 완료',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                content: const Text(
                  '백업 ZIP이 준비되었습니다.\n저장 방법을 선택하세요.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (!saveChoice.isCompleted) {
                        saveChoice.complete(_BackupSaveAction.cancel);
                      }
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (!saveChoice.isCompleted) {
                        saveChoice.complete(_BackupSaveAction.folder);
                      }
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('폴더에 저장'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (!saveChoice.isCompleted) {
                        saveChoice.complete(_BackupSaveAction.share);
                      }
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('공유로 내보내기'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;

    late final String tempZipPath;
    try {
      tempZipPath = await viewModel.exportBackup(
        onProgress: (p) => progress.value = p,
      );
    } catch (e) {
      if (dialogContext.mounted) {
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
      progress.dispose();
      phase.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('백업 실패: $e')));
      }
      return;
    }

    progress.value = BackupExportProgress(
      stage: 'done',
      message: '압축 완료',
      current: progress.value.total,
      total: progress.value.total,
    );
    // 같은 다이얼로그를 저장 선택 UI로 전환
    phase.value = _BackupDialogPhase.chooseSave;

    final action = await saveChoice.future;
    progress.dispose();
    phase.dispose();

    // 다이얼로그는 버튼에서 이미 pop됨. 안전하게 한 프레임 대기
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final host = context.mounted
        ? context
        : (dialogContext.mounted ? dialogContext : null);
    if (host == null) return;

    if (action == _BackupSaveAction.cancel) return;

    if (action == _BackupSaveAction.share) {
      if (!host.mounted) return;
      await _shareBackupAndNotify(host, viewModel, tempZipPath);
      return;
    }

    BackupSaveResult? saved;
    Object? saveError;
    try {
      saved = await viewModel.saveBackupToChosenFolder(tempZipPath);
    } catch (e) {
      saveError = e;
      saved = null;
    }

    // Android SAF가 실패한 경우에만 데스크톱용 saveFile 폴백
    if (saved == null && saveError == null && host.mounted) {
      try {
        saved = await viewModel.saveBackupWithSaveDialog(tempZipPath);
      } catch (e) {
        saveError = e;
        saved = null;
      }
    }

    if (!host.mounted) return;

    if (saved == null) {
      // 사용자가 취소한 경우(에러 없음)는 조용히 종료
      if (saveError == null) return;

      final useShare = await showDialog<bool>(
        context: host,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            '저장 실패',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Text(
            '백업 ZIP을 저장하지 못했습니다.\n$saveError\n\n공유로 내보내시겠습니까?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('공유로 내보내기'),
            ),
          ],
        ),
      );
      if (useShare == true && host.mounted) {
        await _shareBackupAndNotify(host, viewModel, tempZipPath);
      }
      return;
    }

    final result = saved;
    await showDialog<void>(
      context: host,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          '백업 저장 완료',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SelectableText(
          result.isContentUri
              ? '선택한 폴더에 백업 ZIP을 저장했습니다.\n\n${result.location}'
              : result.location,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          if (result.canOpenViaSaf)
            TextButton(
              onPressed: () async {
                try {
                  await viewModel.openSavedBackup(result);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      host,
                    ).showSnackBar(SnackBar(content: Text('열기 실패: $e')));
                  }
                }
              },
              child: const Text('열기'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareBackupAndNotify(
    BuildContext context,
    SettingsViewModel viewModel,
    String tempZipPath,
  ) async {
    try {
      await viewModel.shareBackupFile(tempZipPath);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('공유 시트로 백업을 내보냈습니다.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('공유 실패: $e')));
      }
    }
  }

  Future<void> _importBackup(
    BuildContext context,
    SettingsViewModel viewModel,
  ) async {
    String? zipPath;
    try {
      zipPath = await viewModel.pickBackupZipForImport();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('파일 선택 실패: $e')));
      }
      return;
    }
    if (zipPath == null || zipPath.isEmpty) return;

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          '백업 가져오기',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          '기존 데이터(DB 및 사진)를 선택한 백업으로 덮어씁니다.\n계속할까요?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '취소',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '가져오기',
              style: TextStyle(color: AppColors.messier),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final progress = ValueNotifier(
      const BackupExportProgress(stage: 'preparing', message: '백업 파일 읽는 중…'),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            '백업 가져오기',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: _BackupProgressBody(progress: progress),
        ),
      ),
    );

    try {
      await viewModel.importBackup(
        zipPath,
        onProgress: (p) => progress.value = p,
      );
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업이 복원되었습니다. 앱을 재시작해 주세요.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('가져오기 실패: $e')));
      }
    } finally {
      progress.dispose();
    }
  }
}

enum _BackupDialogPhase { packing, chooseSave }

enum _BackupSaveAction { folder, share, cancel }

/// 백업 진행 다이얼로그 본문 — ValueNotifier만 갱신해 전체가 멈추지 않게 한다.
class _BackupProgressBody extends StatelessWidget {
  const _BackupProgressBody({required this.progress});

  final ValueNotifier<BackupExportProgress> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackupExportProgress>(
      valueListenable: progress,
      builder: (context, state, _) {
        final fraction = state.fraction;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              state.message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: AppColors.textSecondary.withValues(alpha: 0.2),
                color: AppColors.messier,
              ),
            ),
            if (state.total > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${state.current} / ${state.total}',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────
// Shared card wrapper
// ──────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: child,
      ),
    );
  }
}
