import 'package:flutter/material.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_object.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_registration_service.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../catalog/view/metadata_review_screen.dart';

/// 사진 우선 등록 확인 화면 — 요약 정보 확인 후 [등록].
class PhotoFirstConfirmScreen extends StatelessWidget {
  const PhotoFirstConfirmScreen({
    super.key,
    required this.payload,
    required this.object,
    this.photoIndex,
    this.photoTotal,
    this.previewLocalPath,
    this.autoDetected = false,
  });

  final PhotoRegistrationPayload payload;
  final CatalogObject object;
  final int? photoIndex;
  final int? photoTotal;
  final String? previewLocalPath;

  /// Plate Solve 기반 대상 인식 후보 중에서 사용자가 확정한 대상인지 여부.
  final bool autoDetected;

  String _formatCapturedAt() {
    final date = payload.exifInfo.date;
    if (date.isEmpty) return '-';
    return MetadataFormat.formatDateTimeInput(date);
  }

  String _formatGps() {
    final lat = payload.exifInfo.lat;
    final lng = payload.exifInfo.lng;
    if (lat == null || lng == null) return '-';
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  String _formatStack() {
    final stack = payload.exifInfo.stackNum;
    if (stack == null) return '-';
    return '$stack';
  }

  Future<void> _openDetailEdit(BuildContext context) async {
    await AppFileImage.precacheThumbnail(context, payload.localPath);
    if (!context.mounted) return;
    final confirmed = await Navigator.of(context).push<ConfirmedMetadata>(
      MaterialPageRoute(
        builder: (_) => MetadataReviewScreen(
          photoPath: payload.localPath,
          exifInfo: payload.exifInfo,
          objectDisplayId: object.displayName,
          objectName: object.displayCommonName,
        ),
      ),
    );
    if (!context.mounted || confirmed == null) return;
    Navigator.of(context).pop(confirmed);
  }

  void _onRegister(BuildContext context) {
    final confirmed = ConfirmedMetadata.fromExif(
      payload.exifInfo,
      targetName: object.displayId,
    );
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    final exif = payload.exifInfo;
    final color = object.catalog.accentColor;
    final progressLabel = photoIndex != null && photoTotal != null
        ? '$photoIndex / $photoTotal'
        : null;
    final displayPath = photoTotal != null &&
            photoTotal! > 1 &&
            previewLocalPath != null
        ? previewLocalPath!
        : payload.localPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('사진 등록 확인'),
        actions: [
          if (progressLabel != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  progressLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        children: [
          _TargetCard(
            object: object,
            accentColor: color,
            autoDetected: autoDetected,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await AppFileImage.precacheForViewer(context, displayPath);
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FullPhotoViewerPage(photoPath: displayPath),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: AppFileImage.thumbnail(
                      path: displayPath,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 220,
                        color: AppColors.surface,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textSecondary,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.zoom_out_map,
                            size: 22,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '전체보기',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '분석된 촬영 정보',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSm),
                _InfoRow(label: '대상명', value: exif.targetName ?? object.displayId),
                _InfoRow(label: '촬영일', value: _formatCapturedAt()),
                _InfoRow(label: 'Stack', value: _formatStack()),
                _InfoRow(
                  label: '적분시간',
                  value: exif.exposure.isNotEmpty ? exif.exposure : '-',
                ),
                _InfoRow(label: 'ISO', value: exif.iso.isNotEmpty ? exif.iso : '-'),
                _InfoRow(label: 'F값', value: exif.fstop.isNotEmpty ? exif.fstop : '-'),
                _InfoRow(label: 'GPS', value: _formatGps()),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          OutlinedButton.icon(
            onPressed: () => _openDetailEdit(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('상세 입력 · 메타 수정'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingLg,
            AppTheme.spacingSm,
            AppTheme.spacingLg,
            AppTheme.spacingLg,
          ),
          child: FilledButton(
            onPressed: () => _onRegister(context),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text(
              '등록',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.object,
    required this.accentColor,
    this.autoDetected = false,
  });

  final CatalogObject object;
  final Color accentColor;
  final bool autoDetected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withAlpha(64), accentColor.withAlpha(20)],
        ),
        border: Border.all(color: accentColor.withAlpha(102)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  object.catalog.label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (autoDetected) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withAlpha(102)),
                  ),
                  child: Text(
                    'Plate Solve로 인식된 대상',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            object.displayName,
            style: TextStyle(
              color: accentColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            object.displayCommonName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
