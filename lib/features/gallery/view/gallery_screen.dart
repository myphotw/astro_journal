import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/analysis_status.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../core/constants/gallery_object_category.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/shooting_record.dart';
import '../../../shared/widgets/app_file_image.dart';
import '../../../shared/widgets/double_tap_date_picker.dart';
import '../../../shared/widgets/inline_catalog_search_results.dart';
import '../../../shared/widgets/responsive_filter_chips.dart';
import '../viewmodel/gallery_view_model.dart';
import 'gallery_detail_screen.dart';

Color _catalogColor(CatalogType? type) => type?.accentColor ?? AppColors.messier;

int _gridCrossAxisCount(double width) {
  if (width >= 840) return 4;
  if (width >= 600) return 3;
  return 2;
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _isSearching = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
        GalleryViewModel,
        ({
          bool loading,
          String? error,
          List<ShootingRecord> filtered,
          GalleryViewMode viewMode,
          GallerySortOrder sortOrder,
          String searchQuery,
          GalleryObjectCategory categoryFilter,
          bool hasActiveFilters,
          bool favoritesOnly,
        })>(
      selector: (_, vm) => (
        loading: vm.isLoading,
        error: vm.errorMessage,
        filtered: vm.filteredRecords,
        viewMode: vm.viewMode,
        sortOrder: vm.sortOrder,
        searchQuery: vm.searchQuery,
        categoryFilter: vm.categoryFilter,
        hasActiveFilters: vm.hasActiveFilters,
        favoritesOnly: vm.favoritesOnly,
      ),
      builder: (context, state, _) {
        final viewModel = context.read<GalleryViewModel>();

        return Scaffold(
          appBar: AppBar(
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'M27, NGC 6853, Dumbbell, 오리온…',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) {
                      viewModel.setSearchQuery(value);
                      setState(() {});
                    },
                  )
                : const Text('갤러리'),
            actions: [
              IconButton(
                icon: Icon(_isSearching ? Icons.close : Icons.search),
                tooltip: _isSearching ? '검색 닫기' : '검색',
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _searchController.clear();
                      viewModel.setSearchQuery('');
                    }
                    _isSearching = !_isSearching;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  state.hasActiveFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  color: state.hasActiveFilters ? AppColors.ic : null,
                ),
                tooltip: '필터',
                onPressed: () => _showFilterSheet(context, viewModel),
              ),
              PopupMenuButton<GallerySortOrder>(
                tooltip: '정렬',
                icon: const Icon(Icons.sort),
                initialValue: state.sortOrder,
                onSelected: viewModel.setSortOrder,
                itemBuilder: (_) => GallerySortOrder.values
                    .map(
                      (order) => PopupMenuItem(
                        value: order,
                        child: Row(
                          children: [
                            if (state.sortOrder == order)
                              const Icon(Icons.check, size: 18)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(order.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              IconButton(
                icon: Icon(
                  state.favoritesOnly ? Icons.star : Icons.star_border,
                  color: state.favoritesOnly ? Colors.amber : null,
                ),
                tooltip: state.favoritesOnly ? '전체 보기' : '즐겨찾기만',
                onPressed: viewModel.toggleFavoritesOnly,
              ),
            ],
          ),
          body: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? Center(child: Text(state.error!))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isSearching)
                          InlineCatalogSearchResults(
                            query: _searchController.text,
                            allObjects: viewModel.allCatalogObjects,
                            onObjectSelected: (object) {
                              _searchController.text = object.displayName;
                              viewModel.setSearchQuery(object.displayName);
                              setState(() => _isSearching = false);
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacingLg,
                            AppTheme.spacingSm,
                            AppTheme.spacingLg,
                            0,
                          ),
                          child: FullWidthSegmentedButton<GalleryViewMode>(
                            segments: const [
                              ButtonSegment(
                                value: GalleryViewMode.byObject,
                                label: Text('천체별'),
                                icon: Icon(Icons.grid_view_outlined, size: 16),
                              ),
                              ButtonSegment(
                                value: GalleryViewMode.byDate,
                                label: Text('날짜별'),
                                icon: Icon(Icons.view_list_outlined, size: 16),
                              ),
                            ],
                            selected: {state.viewMode},
                            onSelectionChanged: (selection) {
                              viewModel.setViewMode(selection.first);
                            },
                          ),
                        ),
                        _CategoryFilterBar(viewModel: viewModel),
                        if (state.hasActiveFilters)
                          _ActiveFilterSummary(viewModel: viewModel),
                        if (state.hasActiveFilters && state.filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppTheme.spacingLg),
                            child: Column(
                              children: [
                                const Text(
                                  '검색 결과가 없습니다.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    viewModel.clearFilters();
                                    setState(() => _isSearching = false);
                                  },
                                  child: const Text('필터 초기화'),
                                ),
                              ],
                            ),
                          )
                        else
                          Expanded(child: _GalleryBody(viewModel: viewModel)),
                      ],
                    ),
        );
      },
    );
  }

  Future<void> _showFilterSheet(
    BuildContext context,
    GalleryViewModel viewModel,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (context) {
        return _GalleryCompositeFilterSheet(viewModel: viewModel);
      },
    );
  }
}

class _GalleryCompositeFilterSheet extends StatefulWidget {
  const _GalleryCompositeFilterSheet({required this.viewModel});

  final GalleryViewModel viewModel;

  @override
  State<_GalleryCompositeFilterSheet> createState() =>
      _GalleryCompositeFilterSheetState();
}

class _GalleryCompositeFilterSheetState
    extends State<_GalleryCompositeFilterSheet> {
  late DateTime? _from;
  late DateTime? _to;
  late String? _location;

  @override
  void initState() {
    super.initState();
    _from = widget.viewModel.filterDateFrom;
    _to = widget.viewModel.filterDateTo;
    _location = widget.viewModel.filterLocation;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({
    required bool isStart,
  }) async {
    final picked = await showDoubleTapDatePicker(
      context,
      initialDate: isStart
          ? (_from ?? DateTime.now())
          : (_to ?? _from ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLg,
        0,
        AppTheme.spacingLg,
        AppTheme.spacingLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '복합 필터',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          _GalleryFilterDateRow(
            label: '촬영 시작일',
            valueText: _from != null ? _formatDate(_from!) : '전체',
            onTap: () => _pickDate(isStart: true),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          _GalleryFilterDateRow(
            label: '촬영 종료일',
            valueText: _to != null ? _formatDate(_to!) : '전체',
            onTap: () => _pickDate(isStart: false),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          _GalleryLocationField(
            selected: _location,
            locations: widget.viewModel.availableLocations,
            onChanged: (value) => setState(() => _location = value),
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  widget.viewModel.clearFilters();
                  Navigator.pop(context);
                },
                child: const Text('초기화'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  widget.viewModel.setDateRange(from: _from, to: _to);
                  widget.viewModel.setLocationFilter(_location);
                  Navigator.pop(context);
                },
                child: const Text('적용'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GalleryLocationField extends StatefulWidget {
  const _GalleryLocationField({
    required this.selected,
    required this.locations,
    required this.onChanged,
  });

  final String? selected;
  final List<String> locations;
  final ValueChanged<String?> onChanged;

  @override
  State<_GalleryLocationField> createState() => _GalleryLocationFieldState();
}

class _GalleryLocationFieldState extends State<_GalleryLocationField> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.selected ?? '전체';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.place_outlined,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '장소',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          softWrap: true,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _locationTile(null, '전체'),
                  ...widget.locations.map(
                    (location) => _locationTile(location, location),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _locationTile(String? value, String label) {
    final selected = widget.selected == value ||
        (value == null && widget.selected == null);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: selected,
      title: Text(
        label,
        softWrap: true,
        maxLines: null,
        style: const TextStyle(fontSize: 14),
      ),
      onTap: () {
        widget.onChanged(value);
        setState(() => _expanded = false);
      },
    );
  }
}

class _GalleryFilterDateRow extends StatelessWidget {
  const _GalleryFilterDateRow({
    required this.label,
    required this.valueText,
    required this.onTap,
  });

  final String label;
  final String valueText;
  final VoidCallback onTap;

  static const _calendarIcon = Icons.calendar_today_outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMd,
            vertical: 10,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  _calendarIcon,
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterSummary extends StatelessWidget {
  const _ActiveFilterSummary({required this.viewModel});

  final GalleryViewModel viewModel;

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (viewModel.filterDateFrom != null || viewModel.filterDateTo != null) {
      final from = viewModel.filterDateFrom != null
          ? _formatDate(viewModel.filterDateFrom!)
          : '…';
      final to = viewModel.filterDateTo != null
          ? _formatDate(viewModel.filterDateTo!)
          : '…';
      chips.add(
        Chip(
          label: Text('날짜 $from ~ $to'),
          onDeleted: () => viewModel.setDateRange(from: null, to: null),
        ),
      );
    }

    if (viewModel.filterLocation != null &&
        viewModel.filterLocation!.isNotEmpty) {
      chips.add(
        Chip(
          label: Text('장소 ${viewModel.filterLocation!}'),
          onDeleted: () => viewModel.setLocationFilter(null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.viewModel});

  final GalleryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ResponsiveFilterChipGrid(
      singleRow: true,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMd,
        AppTheme.spacingSm,
        AppTheme.spacingMd,
        AppTheme.spacingSm,
      ),
      itemCount: GalleryObjectCategory.filterValues.length,
      itemBuilder: (context, index) {
        final category = GalleryObjectCategory.filterValues[index];
        final selected = viewModel.categoryFilter == category;
        return ExpandedFilterChip(
          compact: true,
          label: Text(
            category.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
          selected: selected,
          onSelected: (_) => viewModel.setCategoryFilter(category),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      },
    );
  }
}

class _GalleryBody extends StatelessWidget {
  const _GalleryBody({required this.viewModel});

  final GalleryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.viewMode == GalleryViewMode.byDate) {
      if (viewModel.filteredRecords.isEmpty) {
        return const Center(
          child: Text(
            '표시할 촬영 기록이 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        );
      }
      return _DateGroupedView(viewModel: viewModel);
    }

    if (viewModel.targetGroups.isEmpty) {
      return const Center(
        child: Text(
          '표시할 촬영 기록이 없습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return _ObjectGridView(viewModel: viewModel);
  }
}

// ─── 날짜별 리스트 뷰 ───────────────────────────────────────────────────────

class _DateGroupedView extends StatelessWidget {
  const _DateGroupedView({required this.viewModel});

  final GalleryViewModel viewModel;

  String _formatDate(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[dt.weekday - 1];
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} ($wd)';
  }

  @override
  Widget build(BuildContext context) {
    final groups = viewModel.recordsGroupedByDate;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMd),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingLg,
                AppTheme.spacingMd,
                AppTheme.spacingLg,
                AppTheme.spacingSm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(group.date),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${group.records.length}개',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ...group.records.map(
              (record) => _DateGroupRecordRow(
                record: record,
                catalogObject: viewModel.catalogObjectFor(
                  record.celestialObjectId,
                ),
                onTap: () {
                  final photos = viewModel.photoRecordsForGalleryDetail;
                  if (photos.isEmpty) return;
                  // 대표사진은 썸네일만 — 상세는 항상 목록 1번부터
                  GalleryDetailScreen.open(
                    context,
                    records: photos,
                    record: photos.first,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DateGroupRecordRow extends StatelessWidget {
  const _DateGroupRecordRow({
    required this.record,
    required this.catalogObject,
    required this.onTap,
  });

  final ShootingRecord record;
  final CatalogObject? catalogObject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _catalogColor(catalogObject?.catalog);
    final photoUri = record.galleryThumbnailUri;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLg,
            vertical: AppTheme.spacingSm,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: photoUri != null && photoUri.isNotEmpty
                      ? AppFileImage(
                          path: photoUri,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 160,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) =>
                              const _ListThumbPlaceholder(),
                        )
                      : const _ListThumbPlaceholder(),
                ),
              ),
              const SizedBox(width: AppTheme.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catalogObject?.displayName ?? record.celestialObjectId,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (catalogObject != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        catalogObject!.displayCommonName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (record.location != null &&
                        record.location!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        record.location!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (record.analysisStatus != AnalysisStatus.completed) ...[
                      const SizedBox(height: 4),
                      _AnalysisStatusChip(status: record.analysisStatus),
                    ],
                  ],
                ),
              ),
              if (record.isFavorite)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.star, color: Colors.amber, size: 18),
                ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 대상 자동 분석(Plate Solve) 상태를 나타내는 작은 배지.
/// [AnalysisStatus.completed]는 정상 상태라 표시하지 않는다.
class _AnalysisStatusChip extends StatelessWidget {
  const _AnalysisStatusChip({required this.status});

  final AnalysisStatus status;

  @override
  Widget build(BuildContext context) {
    final isFailed = status == AnalysisStatus.failed;
    final color = isFailed ? Colors.redAccent : AppColors.textSecondary;
    final icon = isFailed ? Icons.error_outline : Icons.hourglass_top;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          status.label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ListThumbPlaceholder extends StatelessWidget {
  const _ListThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: Icon(
          Icons.photo_outlined,
          color: AppColors.textSecondary,
          size: 24,
        ),
      ),
    );
  }
}

// ─── 대상별 그리드 뷰 ──────────────────────────────────────────────────────

class _ObjectGridView extends StatelessWidget {
  const _ObjectGridView({required this.viewModel});

  final GalleryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final groups = viewModel.targetGroups;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridCrossAxisCount(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppTheme.spacingSm,
            mainAxisSpacing: AppTheme.spacingSm,
            childAspectRatio: 0.85,
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return _GalleryGroupCard(
              group: group,
              onTap: () {
                if (group.records.isEmpty) return;
                // 대표사진은 그리드 썸네일만 — 상세는 촬영순 1번부터
                GalleryDetailScreen.open(
                  context,
                  records: group.records,
                  record: group.records.first,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _GalleryGroupCard extends StatelessWidget {
  const _GalleryGroupCard({
    required this.group,
    required this.onTap,
  });

  final TargetGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _catalogColor(group.object.catalog);
    final photoUri = group.representativeRecord.galleryThumbnailUri;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photoUri != null && photoUri.isNotEmpty)
                    AppFileImage(
                      path: photoUri,
                      fit: BoxFit.cover,
                      memCacheWidth: 480,
                      memCacheHeight: 480,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
                    )
                  else
                    const _PhotoPlaceholder(),
                  if (group.photoCount > 1)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _CountBadge(count: group.photoCount),
                    ),
                  if (group.representativeRecord.isFavorite)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.star, color: Colors.amber, size: 20),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.object.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.object.displayCommonName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.photoCount}장',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: Icon(
          Icons.nights_stay_outlined,
          color: AppColors.textSecondary,
          size: 32,
        ),
      ),
    );
  }
}
