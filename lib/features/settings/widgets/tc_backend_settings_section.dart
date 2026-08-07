import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/tc_backend_models.dart';
import '../../../core/theme/app_colors.dart';
import '../viewmodel/tc_backend_view_model.dart';

class TcBackendSettingsSection extends StatefulWidget {
  const TcBackendSettingsSection({super.key});

  @override
  State<TcBackendSettingsSection> createState() =>
      _TcBackendSettingsSectionState();
}

class _TcBackendSettingsSectionState extends State<TcBackendSettingsSection> {
  final _controller = TextEditingController();
  var _enabled = false;
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final viewModel = context.read<TcBackendViewModel>();
    viewModel.load().then((_) {
      if (!mounted) return;
      setState(() {
        _controller.text = viewModel.settings.baseUrl;
        _enabled = viewModel.settings.enabled;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TcBackendViewModel>();
    final checking = viewModel.status == TcBackendConnectionStatus.checking;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: checking
                ? null
                : (value) => setState(() => _enabled = value),
            title: const Text(
              'TC-Backend',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              '연결 상태 확인 전용입니다. 업로드와 갤러리는 아직 사용하지 않습니다.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            enabled: !checking,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '서버 주소',
              hintText: 'http://host:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '실제 기기에서는 localhost 대신 Backend가 실행 중인 PC/NAS에 접근 가능한 주소를 입력하세요.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: checking ? null : () => _save(context, viewModel),
                child: const Text('저장'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: checking ? null : () => _test(context, viewModel),
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety_outlined),
                label: Text(checking ? '확인 중' : '연결 테스트'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!viewModel.isBackendSyncAvailable)
            const Text(
              'Backend가 비활성화되어 있습니다.',
              key: Key('sync_backend_disabled'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            _SyncStatusPanel(viewModel: viewModel),
          if (viewModel.result != null) ...[
            const SizedBox(height: 12),
            _ResultPanel(result: viewModel.result!),
          ],
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, TcBackendViewModel viewModel) async {
    try {
      await viewModel.save(baseUrl: _controller.text, enabled: _enabled);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('TC-Backend 설정을 저장했습니다.')));
    } on FormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _test(BuildContext context, TcBackendViewModel viewModel) async {
    await viewModel.testConnection(
      baseUrl: _controller.text,
      enabled: _enabled,
    );
  }
}

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel({required this.viewModel});

  final TcBackendViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final counts = viewModel.syncCounts;
    return Container(
      key: const Key('sync_status_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('동기화', style: TextStyle(color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('대기중 ${counts.queued}건'),
          Text('처리중 ${counts.processing}건'),
          Text('실패 ${counts.failed}건'),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('sync_refresh'),
                onPressed: viewModel.refreshSyncStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('새로고침'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('sync_retry'),
                onPressed: counts.failed > 0 ? viewModel.retryFailedSync : null,
                child: const Text('동기화 재시도'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final TcBackendCheckResult result;

  @override
  Widget build(BuildContext context) {
    final healthy = result.isCompatible;
    final color = healthy ? Colors.greenAccent : AppColors.textSecondary;
    final health = result.health;
    final capabilities = result.capabilities;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.message ?? _label(result.status),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            if (health != null) ...[
              const SizedBox(height: 6),
              Text(
                'Database: ${health.database ?? '-'} · Storage: ${health.storage ?? '-'}',
              ),
              Text('Vision: ${health.vision ?? '-'}'),
            ],
            if (capabilities != null) ...[
              Text(
                'API ${capabilities.apiVersion ?? '-'} · ${capabilities.serviceVersion ?? '-'}',
              ),
              Text(
                'AstroJournal 지원: ${_yesNo(capabilities.supportedServices.any((item) => item.toLowerCase() == 'astrojournal'))}',
              ),
              Text(
                'Upload 계약: service_name ${_yesNo(capabilities.supportsServiceName)} · client_file_id ${_yesNo(capabilities.supportsClientFileId)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _yesNo(bool? value) => value == true ? '예' : '아니오';

  String _label(TcBackendConnectionStatus status) => switch (status) {
    TcBackendConnectionStatus.notConfigured => '설정되지 않음',
    TcBackendConnectionStatus.checking => '확인 중',
    TcBackendConnectionStatus.connected => '연결됨',
    TcBackendConnectionStatus.degraded => '연결됨 (일부 기능 제한)',
    TcBackendConnectionStatus.incompatible => '호환되지 않음',
    TcBackendConnectionStatus.unreachable => '연결 실패',
  };
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.surface,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
