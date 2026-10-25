import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/tc_backend_models.dart';
import '../../../services/tc_backend_settings_service.dart';
import '../viewmodel/tc_backend_view_model.dart';

/// Read-only connection/readiness panel. Credentials and endpoints are part of
/// the application build and are intentionally not editable by end users.
class TcBackendSettingsSection extends StatefulWidget {
  const TcBackendSettingsSection({super.key});

  @override
  State<TcBackendSettingsSection> createState() =>
      _TcBackendSettingsSectionState();
}

class _TcBackendSettingsSectionState extends State<TcBackendSettingsSection> {
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final viewModel = context.read<TcBackendViewModel>();
    viewModel.load().then((_) {
      if (viewModel.status == TcBackendConnectionStatus.notConfigured) {
        return viewModel.testConnection();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TcBackendViewModel>();
    final checking = viewModel.status == TcBackendConnectionStatus.checking;
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_done_outlined),
              title: Text('서비스 연결 상태'),
              subtitle: Text('서버 연결은 앱 설치 시 자동 구성됩니다.'),
            ),
            _ReadinessPanel(viewModel: viewModel),
            const SizedBox(height: 12),
            _SyncStatusPanel(viewModel: viewModel),
            const SizedBox(height: 12),
            _PlateSolveStatusPanel(viewModel: viewModel),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('backend_status_refresh'),
                  onPressed: checking ? null : viewModel.refreshStatus,
                  icon: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('연결 재시도'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('sync_retry'),
                  onPressed: viewModel.syncCounts.failed > 0
                      ? viewModel.retryFailedSync
                      : null,
                  child: const Text('동기화 다시 시도'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateSolveStatusPanel extends StatelessWidget {
  const _PlateSolveStatusPanel({required this.viewModel});

  final TcBackendViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final summary = viewModel.plateSolveSummary;
    return Container(
      key: const Key('plate_solve_summary_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plate Solve',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (viewModel.isLoadingPlateSolveSummary && summary == null)
            const Text('진행현황 확인 중…')
          else if (summary != null) ...[
            Text('총 ${summary.total}건'),
            Text('대기 ${summary.waiting}건'),
            Text('처리 중 ${summary.processing}건'),
            Text('완료 ${summary.completed}건'),
            Text('실패 ${summary.failed}건'),
          ] else
            Text(
              viewModel.plateSolveSummaryError ??
                  (viewModel.isBackendSyncAvailable
                      ? '진행현황을 확인할 수 없습니다.'
                      : 'Backend 연결 후 확인할 수 있습니다.'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          if (viewModel.plateSolveSummaryError != null && summary != null) ...[
            const SizedBox(height: 4),
            Text(
              viewModel.plateSolveSummaryError!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadinessPanel extends StatelessWidget {
  const _ReadinessPanel({required this.viewModel});

  final TcBackendViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final result = viewModel.result;
    final readiness = result?.readiness;
    final connected = result?.isCompatible == true;
    return Container(
      key: const Key('backend_readiness'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusRow(
            label: 'NAS 서버',
            ready: connected,
            text: _connectionStatusText(viewModel),
            readyText: '연결됨',
          ),
          _StatusRow(
            label: '연결 방식',
            ready: connected,
            text: _endpointKindText(viewModel.endpointKind),
          ),
          _StatusRow(
            label: '서버 주소',
            ready: connected,
            text: viewModel.settings.baseUrl.isEmpty
                ? '구성되지 않음'
                : viewModel.settings.baseUrl,
          ),
          if (result?.message != null && !connected) ...[
            const SizedBox(height: 6),
            Text(
              result!.message!,
              key: const Key('backend_connection_error'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const Divider(height: 16),
          _StatusRow(label: 'Google 지도', text: '앱에 구성됨', ready: true),
          _StatusRow(
            label: '날씨',
            ready: readiness?.configured('weather') == true,
          ),
          _StatusRow(
            label: '위치 검색',
            ready:
                readiness?.configured('google_geocoding') == true &&
                readiness?.configured('google_places') == true,
          ),
          _StatusRow(
            label: 'Plate Solve',
            ready: readiness?.configured('astrometry') == true,
          ),
        ],
      ),
    );
  }

  String _connectionStatusText(TcBackendViewModel viewModel) =>
      switch (viewModel.status) {
        TcBackendConnectionStatus.checking => '연결 확인 중…',
        TcBackendConnectionStatus.connected => '연결됨',
        TcBackendConnectionStatus.degraded => '연결됨 (일부 기능 제한)',
        TcBackendConnectionStatus.authenticationFailed => '인증 실패',
        TcBackendConnectionStatus.incompatible => '호환되지 않는 서버',
        TcBackendConnectionStatus.serverError => '서버 오류',
        TcBackendConnectionStatus.securityError => '보안 연결 오류',
        TcBackendConnectionStatus.unreachable => '연결 실패',
        TcBackendConnectionStatus.notConfigured => '구성 확인 필요',
      };

  String _endpointKindText(TcBackendEndpointKind? kind) => switch (kind) {
    TcBackendEndpointKind.internal => '내부',
    TcBackendEndpointKind.external => '외부',
    TcBackendEndpointKind.legacy || TcBackendEndpointKind.custom => '기본',
    null => '선택되지 않음',
  };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.ready,
    this.text,
    this.readyText = '사용 가능',
  });

  final String label;
  final bool ready;
  final String? text;
  final String readyText;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          text ?? (ready ? readyText : '서버 연결 필요'),
          style: TextStyle(
            color: ready ? Colors.greenAccent : AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
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
          const Text('동기화', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('대기중 ${counts.queued}건'),
          Text('처리중 ${counts.processing}건'),
          Text('실패 ${counts.failed}건'),
        ],
      ),
    );
  }
}
