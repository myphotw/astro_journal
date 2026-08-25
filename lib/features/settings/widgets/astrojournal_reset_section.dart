import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/astrojournal_reset.dart';
import '../../../services/tc_backend_astrojournal_reset_service.dart';
import '../viewmodel/settings_view_model.dart';

class AstroJournalResetSection extends StatelessWidget {
  const AstroJournalResetSection({super.key, this.onCompleted});

  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SettingsViewModel>();
    final isLoading = viewModel.isLoading;
    return Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever_outlined,
            color: isLoading ? AppColors.textSecondary : Colors.redAccent,
          ),
          title: const Text(
            '촬영 데이터 초기화',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          subtitle: const Text(
            '등록한 촬영 사진과 촬영 기록을 삭제하고 처음부터 다시 구성합니다.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          enabled: !isLoading,
          onTap: isLoading ? null : () => _startReset(context, viewModel),
        ),
      ),
    );
  }

  Future<void> _startReset(
    BuildContext context,
    SettingsViewModel viewModel,
  ) async {
    AstroJournalResetPreview preview;
    try {
      preview = await viewModel.previewCaptureReset();
    } catch (error) {
      if (!context.mounted) return;
      await _showMessage(
        context,
        title: '초기화 정보를 불러오지 못했습니다',
        message: SettingsViewModel.resetUserMessage(error),
      );
      return;
    }
    if (!context.mounted) return;

    if (preview.resetBlocked) {
      final retry = await _showBlocked(context, preview.processingJobCount);
      if (retry == true && context.mounted) {
        await _startReset(context, viewModel);
      }
      return;
    }

    final proceed = await _showPreview(context, preview);
    if (proceed != true || !context.mounted) return;
    final confirmed = await _showConfirmation(context);
    if (confirmed != true || !context.mounted) return;

    try {
      await viewModel.executeCaptureReset();
    } catch (error) {
      if (!context.mounted) return;
      final isBlocked =
          error is AstroJournalResetException &&
          error.type == AstroJournalResetErrorType.blocked;
      await _showMessage(
        context,
        title: isBlocked ? '초기화 대기 필요' : '초기화하지 못했습니다',
        message: SettingsViewModel.resetUserMessage(error),
      );
      return;
    }
    if (!context.mounted) return;

    await _showMessage(
      context,
      title: '촬영 데이터 초기화 완료',
      message:
          'AstroJournal 촬영 데이터가 초기화되었습니다.\n\n'
          '장비와 관측지 설정은 그대로 유지됩니다.\n'
          '새로 보정한 사진을 다시 등록할 수 있습니다.',
    );
    if (!context.mounted) return;
    if (onCompleted != null) {
      onCompleted!();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<bool?> _showBlocked(BuildContext context, int processingCount) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('초기화 대기 필요'),
        content: Text(
          '사진 처리 작업 $processingCount건이 진행 중입니다.\n'
          '작업이 끝난 뒤 다시 확인해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('다시 확인'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showPreview(
    BuildContext context,
    AstroJournalResetPreview preview,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('촬영 데이터 초기화'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DialogHeading('초기화됩니다'),
              _CountRow('촬영 기록', preview.observationRecordCount, '개'),
              _CountRow('등록 사진', preview.astroFileCount, '장'),
              _CountRow('NAS에서 삭제될 사진', preview.astroOnlyFileCount, '장'),
              _CountRow('대기 중인 업로드', preview.pendingUploadCount, '건'),
              const SizedBox(height: 16),
              const Text(
                'AstroJournal 전용으로 등록된 촬영 사진은 NAS에서도 삭제됩니다. '
                '삭제된 촬영 사진은 복구할 수 없습니다.',
                style: TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              const _DialogHeading('보존됩니다'),
              _CountRow(
                '다른 서비스와 공유된 사진',
                preview.preservedSharedFileCount,
                '장',
              ),
              const Text(
                '다른 서비스에서 사용 중인 공유 사진은 삭제되지 않습니다.\n'
                '장비 · 관측지 · Horizon · Catalog · 앱 설정',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('reset-preview-continue'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('계속'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmation(BuildContext context) async {
    var enabled = false;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('마지막 확인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('계속하려면 아래에 “초기화”를 입력하세요.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('reset-confirmation-field'),
                autofocus: true,
                onChanged: (value) {
                  final next = value.trim() == '초기화';
                  if (next != enabled) setState(() => enabled = next);
                },
                decoration: const InputDecoration(hintText: '초기화'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              key: const Key('reset-execute-button'),
              onPressed: enabled
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('촬영 데이터 초기화'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

class _DialogHeading extends StatelessWidget {
  const _DialogHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

class _CountRow extends StatelessWidget {
  const _CountRow(this.label, this.count, this.unit);
  final String label;
  final int count;
  final String unit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text('$count$unit')],
    ),
  );
}
