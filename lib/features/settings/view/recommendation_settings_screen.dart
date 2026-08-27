import 'dart:async';

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
/// 저장 시 Home의 현재 결과를 유지한 채 추천·스케줄 재계산을 시작한다.
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
    CatalogType.barnard,
    CatalogType.ldn,
    CatalogType.lbn,
    CatalogType.star,
  ];

  late Set<CatalogType> _enabledCatalogs;
  late RecommendationPriorityMode _priorityMode;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final service = context.read<RecommendationSettingsService>();
    final settings = await service.load();
    if (!mounted) return;
    setState(() {
      _enabledCatalogs = Set.of(settings.enabledCatalogs);
      _priorityMode = settings.priorityMode;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    if (_enabledCatalogs.isEmpty) {
      _showError('최소 하나 이상의 카탈로그를 선택해야 합니다.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final settings = RecommendationSettings(
        enabledCatalogs: Set.of(_enabledCatalogs),
        azimuthStart: 0,
        azimuthEnd: 359,
        minAltitude: 0,
        maxAltitude: 90,
        priorityMode: _priorityMode,
      );
      await context.read<RecommendationSettingsService>().save(settings);
      if (!mounted) return;
      unawaited(
        context.read<HomeViewModel>().updateRecommendationSettings(settings),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('추천 설정이 저장되었습니다.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showError('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
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
      RecommendationPriorityMode.uncapturedFirst => '미촬영 대상을 항상 먼저 표시합니다.',
      RecommendationPriorityMode.scoreFirst => '추천 점수가 높은 대상을 우선합니다.',
      RecommendationPriorityMode.mixed => '점수와 미촬영 여부를 함께 반영합니다.',
    };
  }

  Widget _buildNote() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.textSecondary.withAlpha(60)),
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
            '• 관측 방향과 고도는 현재 전역 제한 없이 계산합니다.\n'
            '• 관측지 Horizon 반영은 다음 단계에서 제공됩니다.\n'
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
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMd,
              vertical: AppTheme.spacingSm,
            ),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      ],
    );
  }
}
