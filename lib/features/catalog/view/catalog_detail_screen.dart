import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/constants/detect_method.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/shooting_record.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../../shared/widgets/catalog_exposure_guidance_section.dart';
import '../../../shared/widgets/catalog_imaging_availability_section.dart';
import '../../../shared/widgets/equipment_recommendation_section.dart';
import '../../../shared/widgets/sky_map_location_button.dart';
import '../../gallery/view/gallery_detail_screen.dart';
import '../../photo_first/models/registration_session.dart';
import '../../photo_first/services/registration_image_cache.dart';
import '../../photo_first/view/registration_screen.dart';
import '../viewmodel/catalog_detail_view_model.dart';

class CatalogDetailScreen extends StatefulWidget {
  const CatalogDetailScreen({super.key});

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  PageController? _pageController;
  bool _pageReady = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pageReady) {
      final viewModel = context.read<CatalogDetailViewModel>();
      if (viewModel.canSwipe) {
        _pageController = PageController(initialPage: viewModel.currentIndex);
      }
      _pageReady = true;
    }
    // 전환 애니메이션과 DB/장비 로드가 겹치지 않도록 첫 프레임 이후로 미룬다.
    if (!_loadStarted) {
      _loadStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<CatalogDetailViewModel>().load();
      });
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    context.read<CatalogDetailViewModel>().onPageChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CatalogDetailViewModel>();
    final object = viewModel.object;
    final accentColor = object.catalog.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(object.displayName),
            if (viewModel.positionLabel != null)
              Text(
                viewModel.positionLabel!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (viewModel.canDelete)
            IconButton(
              key: const Key('catalog-delete-button'),
              icon: const Icon(Icons.delete_outline),
              tooltip: '사용자 대상 삭제',
              onPressed: () => _showDeleteDialog(context, viewModel),
            ),
        ],
      ),
      body: viewModel.canSwipe
          ? PageView.builder(
              controller: _pageController,
              itemCount: viewModel.objectCount,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                return _CatalogDetailPage(
                  object: viewModel.objectAt(index),
                  accentColor: viewModel.objectAt(index).catalog.accentColor,
                  isActive: index == viewModel.currentIndex,
                );
              },
            )
          : _CatalogDetailPage(
              object: object,
              accentColor: accentColor,
              isActive: true,
            ),
      floatingActionButton: _AddPhotoFab(accentColor: accentColor),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    CatalogDetailViewModel viewModel,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('사용자 대상 삭제'),
        content: Text(
          '"${viewModel.object.displayId}" 대상을 삭제하시겠습니까?\n'
          '이 대상에 연결된 촬영 기록과 사진은 삭제되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await viewModel.deleteObject();
              if (!context.mounted) return;
              if (viewModel.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(viewModel.errorMessage!)),
                );
                return;
              }
              if (viewModel.objects.isEmpty) {
                Navigator.of(context).pop(true);
                return;
              }
              _pageController?.jumpToPage(viewModel.currentIndex);
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

class _CatalogDetailPage extends StatelessWidget {
  const _CatalogDetailPage({
    required this.object,
    required this.accentColor,
    required this.isActive,
  });

  final CatalogObject object;
  final Color accentColor;
  final bool isActive;

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!isActive) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _HeaderCard(
            displayId: object.displayName,
            name: object.displayCommonName,
            accentColor: accentColor,
            captured: object.captured,
          ),
        ],
      );
    }

    final viewModel = context.watch<CatalogDetailViewModel>();
    final alias = object.displayAliases.isNotEmpty
        ? object.displayAliases.join(', ')
        : '-';
    final crossCatalog = object.displayCrossCatalogRefs.isNotEmpty
        ? object.displayCrossCatalogRefs.join(', ')
        : '-';

    final lastCapturedText = viewModel.lastCapturedAt != null
        ? _formatDate(viewModel.lastCapturedAt!)
        : (object.capturedDate ?? '-');

    if (viewModel.isLoading && viewModel.records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _HeaderCard(
          displayId: object.displayName,
          name: object.displayCommonName,
          accentColor: accentColor,
          captured: viewModel.isCaptured,
        ),
        const SizedBox(height: 12),
        SkyMapLocationButton(object: object, popBeforeNavigate: false),
        const SizedBox(height: 12),
        _InfoSection(
          items: [
            _InfoItem(label: '대표명', value: object.displayName),
            _InfoItem(label: '교차 카탈로그', value: crossCatalog, multiline: true),
            _InfoItem(label: '통칭', value: object.displayCommonName),
            _InfoItem(label: '별칭', value: alias, multiline: true),
            _InfoItem(label: '분류', value: object.displayType),
            _InfoItem(label: '별자리', value: object.displayConstellation),
            _InfoItem(label: '계절', value: object.displaySeason),
            _InfoItem(label: '크기', value: object.displayAngularSize),
            _InfoItem(label: '등급', value: object.magnitude),
            if (object.displayDistanceLy != null)
              _InfoItem(label: '거리', value: object.displayDistanceLy!),
          ],
        ),
        if (object.detailDescription != null) ...[
          const SizedBox(height: 12),
          _DescriptionCard(description: object.detailDescription!),
        ],
        if (viewModel.exposureGuidance != null) ...[
          const SizedBox(height: 12),
          CatalogImagingAvailabilitySection(
            sites: viewModel.observationSites,
            selectedSite: viewModel.selectedObservationSite,
            availability: viewModel.imagingAvailability,
            isLoading: viewModel.isAvailabilityLoading,
            onSelectSite: viewModel.selectObservationSite,
          ),
          const SizedBox(height: 12),
          CatalogExposureGuidanceSection(guidance: viewModel.exposureGuidance!),
        ],
        const SizedBox(height: 12),
        EquipmentRecommendationSection(
          recommendation: viewModel.equipmentRecommendation,
        ),
        const SizedBox(height: 12),
        _InfoSection(
          title: '촬영 정보',
          items: [
            _InfoItem(
              label: '촬영 여부',
              value: viewModel.isCaptured ? '촬영 완료' : '미촬영',
              valueColor: viewModel.isCaptured
                  ? accentColor
                  : AppColors.textSecondary,
            ),
            _InfoItem(
              label: '촬영 횟수',
              value: viewModel.isLoading ? '-' : '${viewModel.captureCount}회',
            ),
            _InfoItem(label: '마지막 촬영일', value: lastCapturedText),
          ],
        ),
        if (viewModel.records.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PhotoListSection(
            records: viewModel.records,
            representative: viewModel.representativeRecord,
            onRefresh: () => viewModel.load(),
            onSetRepresentative: viewModel.setRepresentativePhoto,
          ),
        ] else if (viewModel.isCaptured && viewModel.captureCount > 0) ...[
          const SizedBox(height: 12),
          _PhotoPendingCard(onRefresh: viewModel.load),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.displayId,
    required this.name,
    required this.accentColor,
    required this.captured,
  });

  final String displayId;
  final String name;
  final Color accentColor;
  final bool captured;

  @override
  Widget build(BuildContext context) {
    final showName = name != displayId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withAlpha(80), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                displayId,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Icon(
                captured ? Icons.check_circle : Icons.circle_outlined,
                color: captured ? accentColor : AppColors.textSecondary,
                size: 28,
              ),
            ],
          ),
          if (showName) ...[
            const SizedBox(height: 4),
            Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '상세 설명',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const Divider(height: 16, color: AppColors.textSecondary),
          Text(
            description,
            softWrap: true,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({this.title, required this.items});

  final String? title;
  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const Divider(height: 16, color: AppColors.textSecondary),
          ],
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.value,
                      maxLines: item.multiline ? null : 1,
                      overflow: item.multiline
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: item.multiline,
                      style: TextStyle(
                        color: item.valueColor ?? AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.multiline = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool multiline;
}

class _PhotoListSection extends StatelessWidget {
  const _PhotoListSection({
    required this.records,
    required this.representative,
    required this.onRefresh,
    required this.onSetRepresentative,
  });

  final List<ShootingRecord> records;
  final ShootingRecord? representative;
  final VoidCallback onRefresh;
  final Future<void> Function(String recordId) onSetRepresentative;

  @override
  Widget build(BuildContext context) {
    final withPhoto = records
        .where((r) => r.photoUri != null && r.photoUri!.isNotEmpty)
        .toList();

    return Container(
      key: const Key('catalog-photo-list'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '촬영 사진',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${withPhoto.length}장',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: AppColors.textSecondary),
          if (representative != null) ...[
            const Text(
              '대표 사진',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _RepresentativePhoto(
              record: representative!,
              allRecords: records,
              onRefresh: onRefresh,
            ),
            const SizedBox(height: 16),
          ],
          if (withPhoto.length > 1) ...[
            const Text(
              '썸네일 (길게 눌러 대표 지정)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: withPhoto.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final record = withPhoto[index];
                  return _ThumbnailTile(
                    record: record,
                    allRecords: records,
                    isRepresentative: record.isRepresentative,
                    onRefresh: onRefresh,
                    onSetRepresentative: () => onSetRepresentative(record.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...records.map(
            (record) => _PhotoItem(
              record: record,
              allRecords: records,
              onRefresh: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPendingCard extends StatelessWidget {
  const _PhotoPendingCard({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('catalog-photo-pending'),
      child: ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text('촬영 사진을 불러오지 못했습니다.'),
        subtitle: const Text('네트워크 또는 Gallery 캐시 상태를 확인해 주세요.'),
        trailing: IconButton(
          tooltip: '촬영 사진 새로고침',
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

class _RepresentativePhoto extends StatelessWidget {
  const _RepresentativePhoto({
    required this.record,
    required this.allRecords,
    required this.onRefresh,
  });

  final ShootingRecord record;
  final List<ShootingRecord> allRecords;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: AppFileImage(
            path: record.photoUri!,
            fit: BoxFit.cover,
            memCacheWidth: 720,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(
              color: AppColors.background,
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    await GalleryDetailScreen.open(
      context,
      records: allRecords,
      record: record,
    );
    onRefresh();
  }
}

class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.record,
    required this.allRecords,
    required this.isRepresentative,
    required this.onRefresh,
    required this.onSetRepresentative,
  });

  final ShootingRecord record;
  final List<ShootingRecord> allRecords;
  final bool isRepresentative;
  final VoidCallback onRefresh;
  final VoidCallback onSetRepresentative;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await GalleryDetailScreen.open(
          context,
          records: allRecords,
          record: record,
        );
        onRefresh();
      },
      onLongPress: onSetRepresentative,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AppFileImage(
              path: record.photoUri!,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              memCacheWidth: 160,
              memCacheHeight: 160,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                width: 80,
                height: 80,
                color: AppColors.background,
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textSecondary,
                  size: 24,
                ),
              ),
            ),
          ),
          if (isRepresentative)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.star, color: AppColors.solar, size: 16),
            ),
        ],
      ),
    );
  }
}

class _PhotoItem extends StatelessWidget {
  const _PhotoItem({
    required this.record,
    required this.allRecords,
    required this.onRefresh,
  });

  final ShootingRecord record;
  final List<ShootingRecord> allRecords;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(record.capturedAt);
    final hasPhoto = record.photoUri != null && record.photoUri!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openDetail(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(photoUri: record.photoUri),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (record.memo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      record.memo,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (hasPhoto)
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openDetail(BuildContext context) async {
    await GalleryDetailScreen.open(
      context,
      records: allRecords,
      record: record,
    );
    onRefresh();
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photoUri});

  final String? photoUri;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final borderRadius = BorderRadius.circular(8);

    if (photoUri == null || photoUri!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: borderRadius,
        ),
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textSecondary,
          size: 28,
        ),
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: AppFileImage(
        path: photoUri!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).round().clamp(64, 512),
        memCacheHeight: (size * 2).round().clamp(64, 512),
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: borderRadius,
          ),
          child: const Icon(
            Icons.broken_image_outlined,
            color: AppColors.textSecondary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _AddPhotoFab extends StatelessWidget {
  const _AddPhotoFab({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Selector<CatalogDetailViewModel, bool>(
      selector: (_, vm) => vm.isPicking,
      builder: (context, isPicking, _) {
        return FloatingActionButton.extended(
          backgroundColor: accentColor,
          foregroundColor: Colors.black,
          onPressed: isPicking
              ? null
              : () => _onPickPhoto(
                  context,
                  context.read<CatalogDetailViewModel>(),
                ),
          icon: isPicking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(
            isPicking ? '메타데이터 분석 중...' : '사진 추가',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  Future<void> _onPickPhoto(
    BuildContext context,
    CatalogDetailViewModel viewModel,
  ) async {
    final payload = await viewModel.pickPhotoAndPrepare();
    if (!context.mounted) return;

    if (payload == null) {
      if (viewModel.errorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(viewModel.errorMessage!)));
      }
      return;
    }

    final session = RegistrationSession(
      payload: payload,
      selectedObject: viewModel.object,
      detectMethod: DetectMethod.manual,
    );
    unawaited(session.ensureThumbnailLoaded());
    unawaited(() async {
      try {
        final enriched = await viewModel.enrichPayload(payload);
        session.applyEnrichedPayload(enriched);
      } catch (e) {
        session.markAnalysisFailed(e);
      }
    }());

    final outcomes = await Navigator.of(context)
        .push<List<RegistrationOutcome>>(
          PageRouteBuilder<List<RegistrationOutcome>>(
            pageBuilder: (context, animation, secondaryAnimation) {
              return RegistrationScreen.single(
                session: session,
                allObjects: const [],
                skipTargetStep: true,
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                    child: child,
                  );
                },
            transitionDuration: const Duration(milliseconds: 260),
          ),
        );

    if (!context.mounted) return;
    if (outcomes == null || outcomes.isEmpty) {
      RegistrationImageCache.evict(session.localPath);
      return;
    }

    final outcome = outcomes.first;
    final saved = await viewModel.savePhotoRecord(
      outcome.session.payload,
      outcome.confirmed,
      plateSolve: outcome.session.plateSolveResult,
    );
    RegistrationImageCache.evict(session.localPath);
    if (!context.mounted) return;

    if (viewModel.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(viewModel.errorMessage!)));
    } else if (saved != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('사진이 저장되었습니다.')));
    }
  }
}
