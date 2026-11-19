import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/navigation/app_navigation_notifier.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_file_image.dart';
import '../../../../shared/widgets/observatory_ui.dart';
import '../../../../shared/widgets/pc_scroll_edge_buttons.dart';
import '../../../gallery/view/gallery_detail_screen.dart';
import '../../../gallery/viewmodel/gallery_view_model.dart';
import 'pc_dashboard_layout.dart';
import 'pc_home_colors.dart';

class PcRecentPhotosPanel extends StatefulWidget {
  const PcRecentPhotosPanel({super.key});

  @override
  State<PcRecentPhotosPanel> createState() => _PcRecentPhotosPanelState();
}

class _PcRecentPhotosPanelState extends State<PcRecentPhotosPanel> {
  GalleryViewModel? _gallery;
  final ScrollController _photosScrollController = ScrollController();
  static const _thumbnailAspectRatio = 1.24;

  @override
  void dispose() {
    _photosScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gallery = context.read<GalleryViewModel>();
    if (identical(_gallery, gallery)) return;
    _gallery = gallery;
    if (!gallery.hasLoaded && !gallery.isLoading) {
      scheduleMicrotask(() => unawaited(gallery.load()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryViewModel>();
    final photos = gallery.recentPhotoRecords;
    final layout = PcDashboardLayout.maybeOf(context);
    final density = layout?.density ?? 0.0;
    final spacious = layout?.spacious ?? false;
    final photoGap = AppTheme.spacingSm + 8 * density;
    final titleSize = 14 + 3 * density;
    final dateSize = 12 + 2 * density;
    final captionGap = 4 + 4 * density;
    return ObservatoryPanel(
      padding: EdgeInsets.all(layout?.panelPadding ?? AppTheme.spacingMd),
      backgroundColor: PcHomeColors.panel,
      borderColor: PcHomeColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ObservatorySectionHeader(
            title: '최근 촬영한 사진',
            icon: Icons.photo_camera_outlined,
            iconColor: PcHomeColors.muted,
            titleColor: PcHomeColors.text,
            trailing: TextButton(
              onPressed: () =>
                  context.read<AppNavigationNotifier>().navigateTo(2),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('전체 갤러리 →'),
            ),
          ),
          SizedBox(height: photoGap),
          if (gallery.isLoading && !gallery.hasLoaded)
            const ObservatoryStateView(message: '사진을 불러오는 중입니다.', loading: true)
          else if (gallery.errorMessage != null && !gallery.hasLoaded)
            ObservatoryStateView(
              message: '사진을 불러오지 못했습니다.',
              action: ObservatoryButton(
                label: '다시 시도',
                onPressed: () => unawaited(gallery.load()),
                backgroundColor: PcHomeColors.card,
                borderColor: PcHomeColors.border,
                foregroundColor: PcHomeColors.text,
              ),
            )
          else if (photos.isEmpty)
            const ObservatoryStateView(message: '아직 등록된 사진이 없습니다.')
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.maxWidth < 500
                      ? 2
                      : constraints.maxWidth < 580
                      ? 3
                      : 4;
                  final cellWidth =
                      (constraints.maxWidth - photoGap * (count - 1)) / count;
                  var thumbnailWidth = math.min(cellWidth, 136 + 170 * density);
                  if (spacious) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final captionHeight =
                        1.4 *
                            (scaler.scale(titleSize) + scaler.scale(dateSize)) +
                        captionGap +
                        1;
                    final widthForHeight =
                        (constraints.maxHeight - captionHeight) *
                        _thumbnailAspectRatio;
                    // If enlarged text needs more space, scroll rather than
                    // shrinking thumbnails below their compact size.
                    thumbnailWidth = math.min(
                      thumbnailWidth,
                      math.max(136.0, widthForHeight),
                    );
                  }
                  final cacheWidth = spacious
                      ? (thumbnailWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(360, 960)
                      : 360;
                  return PcScrollBoundary(
                    child: Scrollbar(
                      controller: _photosScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _photosScrollController,
                        physics: const ClampingScrollPhysics(),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: photoGap,
                          runSpacing: photoGap,
                          children: [
                            for (final record in photos.take(4))
                              SizedBox(
                                width: thumbnailWidth,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap: () => unawaited(
                                    GalleryDetailScreen.open(
                                      context,
                                      records: photos,
                                      record: record,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: _thumbnailAspectRatio,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                          child: AppFileImage(
                                            path: record.photoUri!,
                                            fit: BoxFit.cover,
                                            memCacheWidth: cacheWidth,
                                            memCacheHeight: spacious
                                                ? (cacheWidth /
                                                          _thumbnailAspectRatio)
                                                      .round()
                                                : 292,
                                            filterQuality: FilterQuality.low,
                                            errorBuilder: (_, _, _) =>
                                                const ColoredBox(
                                                  color: PcHomeColors.card,
                                                  child: Icon(
                                                    Icons.broken_image_outlined,
                                                    color: PcHomeColors.muted,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: captionGap),
                                      Text(
                                        gallery
                                                .catalogObjectFor(
                                                  record.celestialObjectId,
                                                )
                                                ?.displayName ??
                                            record.celestialObjectId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: titleSize,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        _photoDate(record.capturedAt),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: dateSize,
                                          color: PcHomeColors.muted,
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
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _photoDate(DateTime capturedAt) {
  final date = capturedAt.toLocal();
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
}
