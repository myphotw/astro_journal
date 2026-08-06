import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/constants/recommendation_priority_mode.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/home/viewmodel/home_view_model.dart';
import '../../../services/recommendation_settings_service.dart';

/// 추천 대상 필터 설정 화면.
///
/// 저장 시 [HomeViewModel.load]를 호출하여 추천 목록을 즉시 갱신한다.
class RecommendationSettingsScreen extends StatefulWidget {
  const RecommendationSettingsScreen({super.key});

  @override
  State<RecommendationSettingsScreen> createState() =>
      _RecommendationSettingsScreenState();
}

class _RecommendationSettingsScreenState
    extends State<RecommendationSettingsScreen> {
  static const _recommendableCatalogs = [
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
    CatalogType.caldwell,
    CatalogType.rcw,
    CatalogType.vdb,
    CatalogType.star,
  ];

  late Set<CatalogType> _enabledCatalogs;
  late TextEditingController _azStartCtrl;
  late TextEditingController _azEndCtrl;
  late TextEditingController _altMinCtrl;
  late TextEditingController _altMaxCtrl;
  late RecommendationPriorityMode _priorityMode;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _azStartCtrl = TextEditingController();
    _azEndCtrl = TextEditingController();
    _altMinCtrl = TextEditingController();
    _altMaxCtrl = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _azStartCtrl.dispose();
    _azEndCtrl.dispose();
    _altMinCtrl.dispose();
    _altMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final service = context.read<RecommendationSettingsService>();
    final settings = await service.load();
    if (!mounted) return;
    setState(() {
      _enabledCatalogs = Set.of(settings.enabledCatalogs);
      _azStartCtrl.text = settings.azimuthStart.toString();
      _azEndCtrl.text = settings.azimuthEnd.toString();
      _altMinCtrl.text = settings.minAltitude.toString();
      _altMaxCtrl.text = settings.maxAltitude.toString();
      _priorityMode = settings.priorityMode;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final azStart = int.tryParse(_azStartCtrl.text) ?? 0;
    final azEnd = int.tryParse(_azEndCtrl.text) ?? 359;
    final altMin = int.tryParse(_altMinCtrl.text) ?? 20;
    final altMax = int.tryParse(_altMaxCtrl.text) ?? 90;

    if (azStart < 0 || azStart > 359 || azEnd < 0 || azEnd > 359) {
      _showError('방위각은 0–359° 범위여야 합니다.');
      return;
    }
    if (altMin < 0 || altMin > 90 || altMax < 0 || altMax > 90) {
      _showError('고도는 0–90° 범위여야 합니다.');
      return;
    }
    if (altMin >= altMax) {
      _showError('최소 고도는 최대 고도보다 작아야 합니다.');
      return;
    }
    if (_enabledCatalogs.isEmpty) {
      _showError('최소 하나 이상의 카탈로그를 선택해야 합니다.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = RecommendationSettings(
        enabledCatalogs: Set.of(_enabledCatalogs),
        azimuthStart: azStart,
        azimuthEnd: azEnd,
        minAltitude: altMin,
        maxAltitude: altMax,
        priorityMode: _priorityMode,
      );
      await context.read<RecommendationSettingsService>().save(settings);
      if (!mounted) return;
      // 홈 뷰모델 즉시 갱신
      await context.read<HomeViewModel>().load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('추천 설정이 저장되었습니다.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showError('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('추천 대상 설정'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                '저장',
                style: TextStyle(
                  color: AppColors.messier,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              children: [
                _buildCatalogSection(),
                const SizedBox(height: AppTheme.spacingXl),
                _buildPrioritySection(),
                const SizedBox(height: AppTheme.spacingXl),
                _buildAzimuthSection(),
                const SizedBox(height: AppTheme.spacingXl),
                _buildAltitudeSection(),
                const SizedBox(height: AppTheme.spacingXl),
                _buildNote(),
              ],
            ),
    );
  }

  // ── 카탈로그 체크박스 ────────────────────────────────────────────────────

  Widget _buildCatalogSection() {
    return _Section(
      icon: Icons.category_outlined,
      title: '추천 카탈로그',
      child: Column(
        children: _recommendableCatalogs.map((catalog) {
          final enabled = _enabledCatalogs.contains(catalog);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _enabledCatalogs.add(catalog);
                } else {
                  _enabledCatalogs.remove(catalog);
                }
              });
            },
            title: Text(
              catalog.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            activeColor: AppColors.messier,
            checkColor: AppColors.background,
            side: const BorderSide(color: AppColors.textSecondary),
          );
        }).toList(),
      ),
    );
  }

  // ── 추천 우선순위 ────────────────────────────────────────────────────────

  Widget _buildPrioritySection() {
    return _Section(
      icon: Icons.sort_outlined,
      title: '추천 우선순위',
      subtitle: '홈 화면 추천 목록의 정렬 기준을 선택합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<RecommendationPriorityMode>(
            segments: RecommendationPriorityMode.values
                .map(
                  (mode) => ButtonSegment<RecommendationPriorityMode>(
                    value: mode,
                    label: Text(
                      mode.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )
                .toList(),
            selected: {_priorityMode},
            onSelectionChanged: (selection) {
              setState(() => _priorityMode = selection.first);
            },
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.background;
                }
                return AppColors.textPrimary;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.messier;
                }
                return AppColors.surface;
              }),
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            _priorityModeDescription(_priorityMode),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _priorityModeDescription(RecommendationPriorityMode mode) {
    return switch (mode) {
      RecommendationPriorityMode.uncapturedFirst =>
        '미촬영 대상을 항상 먼저 표시합니다.',
      RecommendationPriorityMode.scoreFirst => '추천 점수가 높은 대상을 우선합니다.',
      RecommendationPriorityMode.mixed =>
        '점수와 미촬영 여부를 함께 반영합니다.',
    };
  }

  // ── 방위각 ──────────────────────────────────────────────────────────────

  Widget _buildAzimuthSection() {
    return _Section(
      icon: Icons.explore_outlined,
      title: '관측 가능 방위각',
      subtitle: '시작각이 종료각보다 큰 경우(예: 300° ~ 80°)도 지원합니다.',
      child: Row(
        children: [
          Expanded(
            child: _AngleField(
              controller: _azStartCtrl,
              label: '시작 방위각',
              hint: '0',
              suffix: '°',
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Text(
              '~',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
          ),
          Expanded(
            child: _AngleField(
              controller: _azEndCtrl,
              label: '종료 방위각',
              hint: '359',
              suffix: '°',
            ),
          ),
        ],
      ),
    );
  }

  // ── 고도 ────────────────────────────────────────────────────────────────

  Widget _buildAltitudeSection() {
    return _Section(
      icon: Icons.height_outlined,
      title: '관측 가능 고도',
      child: Row(
        children: [
          Expanded(
            child: _AngleField(
              controller: _altMinCtrl,
              label: '최소 고도',
              hint: '20',
              suffix: '°',
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
            child: Text(
              '~',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
          ),
          Expanded(
            child: _AngleField(
              controller: _altMaxCtrl,
              label: '최대 고도',
              hint: '90',
              suffix: '°',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: AppColors.textSecondary.withAlpha(60),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '※ 안내',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '• 방위각: 북=0°, 동=90°, 남=180°, 서=270°\n'
            '• 추천 우선순위는 미촬영·점수·촬영시간 등을 반영합니다.\n'
            '• 조건을 벗어난 대상은 추천에서 제외됩니다.\n'
            '• 저장 후 추천 목록이 즉시 갱신됩니다.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 공통 위젯 ────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.messier),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.messier,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacingMd),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: AppTheme.spacingSm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _AngleField extends StatefulWidget {
  const _AngleField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;

  @override
  State<_AngleField> createState() => _AngleFieldState();
}

class _AngleFieldState extends State<_AngleField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.controller.clear();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        hintText: widget.hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        suffixText: widget.suffix,
        suffixStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.textSecondary),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.messier),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        ),
        isDense: true,
      ),
    );
  }
}
