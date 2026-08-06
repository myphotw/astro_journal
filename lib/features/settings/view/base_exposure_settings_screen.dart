import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/base_exposure_settings_service.dart';

/// 카탈로그 기본 촬영시간 계산용 기준 Bortle 설정 화면.
class BaseExposureSettingsScreen extends StatefulWidget {
  const BaseExposureSettingsScreen({super.key});

  @override
  State<BaseExposureSettingsScreen> createState() =>
      _BaseExposureSettingsScreenState();
}

class _BaseExposureSettingsScreenState extends State<BaseExposureSettingsScreen> {
  int _referenceBortle = BaseExposureSettings.defaultReferenceBortle;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final service = context.read<BaseExposureSettingsService>();
    final settings = await service.load();
    if (!mounted) return;
    setState(() {
      _referenceBortle = settings.referenceBortle;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await context.read<BaseExposureSettingsService>().save(
            BaseExposureSettings(referenceBortle: _referenceBortle),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기준 Bortle 설정을 저장했습니다.')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('기본 촬영환경 설정'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              children: [
                const Text(
                  '카탈로그 천체 상세정보의 기본 촬영시간(최소/권장) 계산에 '
                  '사용할 기준 Bortle 등급입니다.\n'
                  '메인 추천 화면의 실시간 촬영시간과는 별도로 적용됩니다.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '기준 Bortle 등급',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bortle $_referenceBortle',
                          style: const TextStyle(
                            color: AppColors.messier,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Slider(
                          value: _referenceBortle.toDouble(),
                          min: 1,
                          max: 9,
                          divisions: 8,
                          label: 'Bortle $_referenceBortle',
                          onChanged: (value) {
                            setState(() {
                              _referenceBortle = value.round();
                            });
                          },
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '1 (매우 어두움)',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '9 (도심)',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('저장'),
                ),
              ],
            ),
    );
  }
}
