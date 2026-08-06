import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/exif_service.dart';
import '../viewmodel/exif_debug_view_model.dart';

/// 원본·복사본 EXIF, dump, 파서, Pipeline을 단계별로 확인하는 개발용 화면.
class ExifDebugScreen extends StatelessWidget {
  const ExifDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ExifDebugViewModel(
        exifService: ctx.read<ExifService>(),
      ),
      child: const _ExifDebugBody(),
    );
  }
}

class _ExifDebugBody extends StatelessWidget {
  const _ExifDebugBody();

  Future<void> _copyLog(BuildContext context) async {
    final vm = context.read<ExifDebugViewModel>();
    if (!vm.hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 사진을 선택해 주세요.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: vm.buildFullLog()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그가 클립보드에 복사되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ExifDebugViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('EXIF 디버그'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton.icon(
            onPressed: vm.hasData ? () => _copyLog(context) : null,
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('로그 복사'),
          ),
        ],
      ),
      body: vm.isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'EXIF 분석 중...',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : vm.hasData
              ? _ResultScrollView(vm: vm)
              : _EmptyState(
                  error: vm.errorMessage,
                  onPick: vm.pickAndAnalyze,
                ),
      floatingActionButton: vm.isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: vm.pickAndAnalyze,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(vm.hasData ? '다른 사진' : '사진 선택'),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick, this.error});

  final VoidCallback onPick;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bug_report_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              '갤러리에서 사진 1장을 선택하면\n'
              '원본 EXIF · dump · 파서 · Pipeline · copy 비교를\n'
              '한 화면에서 확인할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultScrollView extends StatelessWidget {
  const _ResultScrollView({required this.vm});

  final ExifDebugViewModel vm;

  Future<void> _copyText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클립보드에 복사되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        _DebugCard(
          title: '파일 정보',
          initiallyExpanded: true,
          onCopy: () => _copyText(
            context,
            [
              '원본 파일명: ${vm.originalFilename}',
              'picked.path: ${vm.pickedPath}',
              '파일 크기: ${vm.fileSizeLabel}',
              '복사 전 경로: ${vm.pickedPath}',
              '복사 후 경로: ${vm.copyPath}',
            ].join('\n'),
          ),
          child: _MonoLines([
            '원본 파일명: ${vm.originalFilename}',
            'picked.path: ${vm.pickedPath}',
            '파일 크기: ${vm.fileSizeLabel}',
            '복사 전 경로: ${vm.pickedPath}',
            '복사 후 경로: ${vm.copyPath}',
          ]),
        ),
        _DebugCard(
          title: '원본 EXIF (native_exif)',
          initiallyExpanded: true,
          onCopy: () => _copyText(
            context,
            ExifDebugViewModel.exifDisplayTags
                .map((t) => '$t: ${vm.originalExif[t] ?? "NULL"}')
                .join('\n'),
          ),
          child: _MonoLines(
            ExifDebugViewModel.exifDisplayTags
                .map((t) => '$t: ${vm.originalExif[t] ?? "NULL"}')
                .toList(),
          ),
        ),
        _DebugCard(
          title: 'dumpAllAttributes',
          onCopy: () => _copyText(context, vm.dumpAllJsonPretty()),
          child: _ScrollableMonoText(vm.dumpAllJsonPretty()),
        ),
        if (vm.makerNoteAnalysis != null)
          _DebugCard(
            title: 'MakerNote 분석',
            onCopy: () => _copyText(
              context,
              vm.makerNoteAnalysis!.toLogSection('MakerNote'),
            ),
            child: _SeestarAnalysisBody(analysis: vm.makerNoteAnalysis!),
          ),
        if (vm.cameraOwnerAnalysis != null)
          _DebugCard(
            title: 'CameraOwnerName 분석',
            onCopy: () => _copyText(
              context,
              vm.cameraOwnerAnalysis!.toLogSection('CameraOwnerName'),
            ),
            child: _SeestarAnalysisBody(analysis: vm.cameraOwnerAnalysis!),
          ),
        _DebugCard(
          title: 'PhotoMetadata Pipeline',
          initiallyExpanded: true,
          onCopy: () => _copyText(
            context,
            [
              ...vm.pipelineFields.map((r) => r.displayLine),
              if (vm.pipelineParseTraceLog.isNotEmpty) ...[
                '',
                '--- Pipeline parse() 단계 로그 ---',
                vm.pipelineParseTraceLog.trim(),
              ],
            ].join('\n'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MonoLines(
                vm.pipelineFields.map((r) => r.displayLine).toList(),
              ),
              if (vm.pipelineParseTraceLog.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    '--- Pipeline parse() 단계 로그 ---',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                _ScrollableMonoText(vm.pipelineParseTraceLog.trim(), maxHeight: 240),
              ],
            ],
          ),
        ),
        _DebugCard(
          title: 'File.copy 비교',
          initiallyExpanded: true,
          onCopy: () => _copyText(
            context,
            vm.copyCompareRows.map((r) => r.displayLine).join('\n'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in vm.copyCompareRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    row.displayLine,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeestarAnalysisBody extends StatelessWidget {
  const _SeestarAnalysisBody({required this.analysis});

  final SeestarTagAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    if (analysis.raw == null || analysis.raw!.isEmpty) {
      return const _MonoLines(['(없음)']);
    }

    final lines = <String>[
      '문자 길이: ${analysis.length}',
      '앞 500자:',
      analysis.preview500,
      'JSON 추출: ${analysis.jsonExtractSuccess ? "성공" : "실패"}',
      'JSON Parse: ${analysis.jsonParseSuccess ? "성공" : "실패"}',
    ];

    if (analysis.jsonParseSuccess && analysis.parsed != null) {
      final p = analysis.parsed!;
      lines.addAll([
        'obj_name: ${p.objName ?? "NULL"}',
        'stack_num: ${p.stackNum ?? "NULL"}',
        'exp_sec: ${p.expSec ?? "NULL"}',
        'tot_exp_sec: ${p.totExpSec ?? "NULL"}',
        'lon_lat: ${analysis.formatLonLat()}',
        'creator: ${p.creator ?? "NULL"}',
        'date: ${p.date ?? "NULL"}',
      ]);
    }

    if (analysis.parseTraceLog.isNotEmpty) {
      lines.add('--- parse() 단계 로그 ---');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          if (i == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '앞 500자:',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (i == 2 && lines.length > 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ScrollableMonoText(lines[2], maxHeight: 160),
            )
          else if (i != 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                lines[i],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
        if (analysis.parseTraceLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ScrollableMonoText(
              analysis.parseTraceLog.trim(),
              maxHeight: 240,
            ),
          ),
      ],
    );
  }
}

class _DebugCard extends StatefulWidget {
  const _DebugCard({
    required this.title,
    required this.child,
    this.onCopy,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final VoidCallback? onCopy;
  final bool initiallyExpanded;

  @override
  State<_DebugCard> createState() => _DebugCardState();
}

class _DebugCardState extends State<_DebugCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (widget.onCopy != null)
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: '복사',
                      onPressed: widget.onCopy,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _MonoLines extends StatelessWidget {
  const _MonoLines(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      lines.join('\n'),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
    );
  }
}

class _ScrollableMonoText extends StatelessWidget {
  const _ScrollableMonoText(this.text, {this.maxHeight = 280});

  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            text.isEmpty ? '(없음)' : text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
