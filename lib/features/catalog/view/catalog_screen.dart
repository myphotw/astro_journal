import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/catalog_kind_filter.dart';
import '../../../core/constants/catalog_sort_order.dart';
import '../../../core/constants/catalog_type.dart';
import '../../../core/navigation/app_navigation_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/gallery_shooting_record_repository_adapter.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../data/repositories/equipment_repository.dart';
import '../../../services/equipment/equipment_recommendation_service.dart';
import '../../../services/exposure_policy.dart';
import '../../../services/base_exposure_settings_service.dart';
import '../../../services/object_imaging_profile_provider.dart';
import '../../../services/photo_registration_service.dart';
import '../../../shared/widgets/catalog_object_card.dart';
import '../../../shared/widgets/inline_catalog_search_results.dart';
import '../../../shared/widgets/responsive_filter_chips.dart';
import '../../../services/catalog_metadata_enricher.dart';
import '../../../services/catalog_capture_projection_service.dart';
import '../../../services/metadata_service.dart';
import '../../season/view/season_planner_screen.dart';
import '../../gallery/viewmodel/gallery_view_model.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../stats/viewmodel/stats_view_model.dart';
import '../viewmodel/catalog_detail_view_model.dart';
import '../viewmodel/catalog_view_model.dart'
    show CatalogViewModel, ShootingFilter;
import 'catalog_detail_screen.dart';

int _gridCrossAxisCount(double width) {
  if (width >= 840) return 4;
  if (width >= 600) return 3;
  return 2;
}

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _tabLabels = [
    '전체',
    'Messier',
    'NGC',
    'IC',
    'Caldwell',
    'Sh2',
    'RCW',
    'vdB',
    '별',
    '태양계',
    '은하수',
  ];
  static const List<CatalogType?> _tabTypes = [
    null,
    CatalogType.messier,
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.caldwell,
    CatalogType.sh2,
    CatalogType.rcw,
    CatalogType.vdb,
    CatalogType.star,
    CatalogType.solar,
    CatalogType.milky,
  ];

  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final Map<String, double> _scrollOffsets = {};
  AppNavigationNotifier? _navNotifier;
  bool _tabSynced = false;
  bool _isSearching = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final vm = context.read<CatalogViewModel>();
        _saveScrollPosition(vm);
        vm.selectTab(_tabTypes[_tabController.index]);
        _restoreScrollPosition(vm);
      }
    });
  }

  String _scrollStorageKey(CatalogViewModel vm) =>
      '${vm.selectedTab}_${vm.shootingFilter}_${vm.kindFilter}_${vm.sortOrder}';

  void _saveScrollPosition(CatalogViewModel vm) {
    if (!_scrollController.hasClients) return;
    _scrollOffsets[_scrollStorageKey(vm)] = _scrollController.offset;
  }

  void _restoreScrollPosition(CatalogViewModel vm) {
    final offset = _scrollOffsets[_scrollStorageKey(vm)];
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
    });
  }

  void _onShootingFilterChanged(BuildContext context, ShootingFilter filter) {
    final vm = context.read<CatalogViewModel>();
    _saveScrollPosition(vm);
    vm.selectShootingFilter(filter);
    _restoreScrollPosition(vm);
  }

  void _onKindFilterChanged(BuildContext context, CatalogKindFilter filter) {
    final vm = context.read<CatalogViewModel>();
    _saveScrollPosition(vm);
    vm.selectKindFilter(filter);
    _restoreScrollPosition(vm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tabSynced) {
      _tabSynced = true;
      final tab = context.read<CatalogViewModel>().selectedTab;
      final index = _tabTypes.indexOf(tab);
      if (index > 0) {
        _tabController.index = index;
      }
    }
    final notifier = context.read<AppNavigationNotifier>();
    if (_navNotifier != notifier) {
      _navNotifier?.removeListener(_onNavigationChanged);
      _navNotifier = notifier;
      _navNotifier!.addListener(_onNavigationChanged);
    }
  }

  void _onNavigationChanged() {
    final nav = context.read<AppNavigationNotifier>();
    final pending = nav.pendingCatalogType;
    if (pending == null) return;

    final index = _tabTypes.indexOf(pending);
    if (index >= 0) {
      _tabController.animateTo(index);
      context.read<CatalogViewModel>().selectTab(pending);
    }
    nav.consumePendingCatalogType();
  }

  Future<void> _openCatalogDetail(
    BuildContext context, {
    required CatalogObject object,
    required List<CatalogObject> navigationObjects,
  }) async {
    final catalogRepo = context.read<CatalogRepository>();
    final shootingRepo = context.read<GalleryShootingRecordRepositoryAdapter>();
    final metadataSvc = context.read<MetadataService>();
    final registrationSvc = context.read<PhotoRegistrationService>();
    final equipmentRepo = context.read<EquipmentRepository>();
    final equipmentRecSvc = context.read<EquipmentRecommendationService>();
    final baseExposureSettingsService = context
        .read<BaseExposureSettingsService>();
    final profileProvider = context.read<ObjectImagingProfileProvider>();
    final exposurePolicy = context.read<ExposurePolicy>();
    final catalogVm = context.read<CatalogViewModel>();
    final galleryVm = context.read<GalleryViewModel>();
    final homeVm = context.read<HomeViewModel>();
    final statsVm = context.read<StatsViewModel>();

    _saveScrollPosition(catalogVm);

    final detailVm = CatalogDetailViewModel(
      object,
      shootingRepo,
      catalogRepo,
      registrationSvc,
      metadataSvc,
      equipmentRepo,
      equipmentRecSvc,
      baseExposureSettingsService,
      profileProvider,
      exposurePolicy,
      navigationObjects: navigationObjects,
      captureProjection: context.read<CatalogCaptureProjectionService>(),
    );

    final dataChanged = await Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(
              value: detailVm,
              child: const CatalogDetailScreen(),
            ),
          ),
        )
        .then((_) => detailVm.dataChanged);
    detailVm.dispose();

    if (!context.mounted) return;
    _restoreScrollPosition(catalogVm);

    // 읽기만 한 경우 전체 리로드로 전환 직후 버벅임을 만들지 않는다.
    if (!dataChanged) return;

    unawaited(catalogVm.load(silent: true));
    unawaited(Future.wait([galleryVm.load(), homeVm.load(), statsVm.load()]));
  }

  void _openSearch(BuildContext context) {
    setState(() {
      if (_isSearching) {
        _searchController.clear();
      }
      _isSearching = !_isSearching;
    });
  }

  void _navigateToAddEntry(BuildContext context) {
    final catalogRepo = context.read<CatalogRepository>();
    final shootingRepo = context.read<ShootingRecordRepository>();
    final metadataSvc = context.read<MetadataService>();
    final registrationSvc = context.read<PhotoRegistrationService>();
    final catalogVm = context.read<CatalogViewModel>();
    final galleryVm = context.read<GalleryViewModel>();
    final homeVm = context.read<HomeViewModel>();
    final statsVm = context.read<StatsViewModel>();

    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _AddCatalogEntryScreen(
              catalogRepository: catalogRepo,
              shootingRecordRepository: shootingRepo,
              registrationService: registrationSvc,
              metadataService: metadataSvc,
            ),
          ),
        )
        .then((_) {
          catalogVm.load();
          galleryVm.load();
          homeVm.load();
          statsVm.load();
        });
  }

  @override
  void dispose() {
    _navNotifier?.removeListener(_onNavigationChanged);
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CatalogViewModel>();

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
              )
            : const Text('카탈로그'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '검색 닫기' : '천체 검색',
            onPressed: () => _openSearch(context),
          ),
          PopupMenuButton<CatalogSortOrder>(
            tooltip: '정렬',
            icon: const Icon(Icons.sort),
            initialValue: viewModel.sortOrder,
            onSelected: viewModel.selectSortOrder,
            itemBuilder: (_) => CatalogSortOrder.values
                .map(
                  (order) => PopupMenuItem(
                    value: order,
                    child: Row(
                      children: [
                        if (viewModel.sortOrder == order)
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
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingXs),
            child: FilledButton.tonalIcon(
              onPressed: () => SeasonPlannerScreen.open(context),
              icon: const Icon(Icons.wb_sunny_outlined, size: 16),
              label: const Text('계절별'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.solar.withValues(alpha: 0.18),
                foregroundColor: AppColors.solar,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '새 카탈로그 항목 추가',
            onPressed: () => _navigateToAddEntry(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: viewModel.isLoading && viewModel.allObjects.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : viewModel.errorMessage != null && viewModel.allObjects.isEmpty
          ? Center(child: Text(viewModel.errorMessage!))
          : Column(
              children: [
                if (_isSearching)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    // 검색 결과 위젯의 context는 선택 즉시 트리에서
                    // 제거되므로(_isSearching=false), 네비게이션에는
                    // State의 context(this.context)를 사용해야 한다.
                    builder: (_, value, _) {
                      return InlineCatalogSearchResults(
                        query: value.text,
                        allObjects: viewModel.allObjects,
                        searchIndex: viewModel.searchIndex,
                        onObjectSelected: (object) {
                          final resolved = viewModel.resolveForNavigation(
                            object,
                          );
                          final navigation = viewModel
                              .navigationTargetsForSearch(object);
                          setState(() {
                            _isSearching = false;
                            _searchController.clear();
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            _openCatalogDetail(
                              context,
                              object: resolved,
                              navigationObjects: navigation,
                            );
                          });
                        },
                      );
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLg,
                    vertical: AppTheme.spacingSm,
                  ),
                  child: FullWidthSegmentedButton<ShootingFilter>(
                    segments: const [
                      ButtonSegment(
                        value: ShootingFilter.all,
                        label: Text('전체'),
                      ),
                      ButtonSegment(
                        value: ShootingFilter.captured,
                        label: Text('촬영 완료'),
                      ),
                      ButtonSegment(
                        value: ShootingFilter.notCaptured,
                        label: Text('미촬영'),
                      ),
                    ],
                    selected: {viewModel.shootingFilter},
                    onSelectionChanged: (selection) {
                      _onShootingFilterChanged(context, selection.first);
                    },
                  ),
                ),
                ResponsiveFilterChipGrid(
                  singleRow: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingLg,
                  ),
                  itemCount: CatalogKindFilter.values.length,
                  itemBuilder: (context, index) {
                    final filter = CatalogKindFilter.values[index];
                    final selected = viewModel.kindFilter == filter;
                    return ExpandedFilterChip(
                      compact: true,
                      label: Text(
                        filter.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10),
                      ),
                      selected: selected,
                      onSelected: (_) => _onKindFilterChanged(context, filter),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppTheme.spacingSm),
                Expanded(
                  child: viewModel.objects.isEmpty
                      ? const Center(
                          child: Text(
                            '표시할 천체가 없습니다.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = _gridCrossAxisCount(
                              constraints.maxWidth,
                            );
                            final gridKey = _scrollStorageKey(viewModel);
                            final objects = viewModel.objects;
                            return GridView.builder(
                              key: PageStorageKey<String>(
                                'catalog_grid_$gridKey',
                              ),
                              controller: _scrollController,
                              padding: const EdgeInsets.all(AppTheme.spacingLg),
                              addAutomaticKeepAlives: false,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: AppTheme.spacingSm,
                                    mainAxisSpacing: AppTheme.spacingSm,
                                    childAspectRatio: 1.1,
                                  ),
                              itemCount: objects.length,
                              itemBuilder: (context, index) {
                                final object = objects[index];
                                final thumbnail = viewModel.thumbnailFor(
                                  object.id,
                                );
                                return CatalogObjectCard(
                                  object: object,
                                  thumbnailPath: thumbnail,
                                  equipmentChips: viewModel.equipmentChipsFor(
                                    object.id,
                                  ),
                                  onTap: () {
                                    _openCatalogDetail(
                                      context,
                                      object: object,
                                      navigationObjects: objects,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// 새 카탈로그 항목 추가 화면
// ─────────────────────────────────────────────

class _AddCatalogEntryScreen extends StatefulWidget {
  const _AddCatalogEntryScreen({
    required this.catalogRepository,
    required this.shootingRecordRepository,
    required this.registrationService,
    required this.metadataService,
  });

  final CatalogRepository catalogRepository;
  final ShootingRecordRepository shootingRecordRepository;
  final PhotoRegistrationService registrationService;
  final MetadataService metadataService;

  @override
  State<_AddCatalogEntryScreen> createState() => _AddCatalogEntryScreenState();
}

class _AddCatalogEntryScreenState extends State<_AddCatalogEntryScreen> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _constellationController = TextEditingController();
  final _magnitudeController = TextEditingController();

  CatalogType _selectedCatalog = CatalogType.ngc;
  bool _isSaving = false;

  static const List<CatalogType> _allowedTypes = [
    CatalogType.ngc,
    CatalogType.ic,
    CatalogType.sh2,
  ];

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _typeController.dispose();
    _constellationController.dispose();
    _magnitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 카탈로그 항목 추가')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionLabel('카탈로그 타입'),
            const SizedBox(height: 8),
            SegmentedButton<CatalogType>(
              segments: _allowedTypes
                  .map(
                    (t) => ButtonSegment<CatalogType>(
                      value: t,
                      label: Text(t.label),
                    ),
                  )
                  .toList(),
              selected: {_selectedCatalog},
              onSelectionChanged: (s) =>
                  setState(() => _selectedCatalog = s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _numberController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '번호 *',
                hintText: '예: 7331',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '번호를 입력하세요';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return '올바른 숫자를 입력하세요';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름/별칭',
                hintText: '예: Andromeda Galaxy',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _typeController,
              decoration: const InputDecoration(
                labelText: '천체 분류',
                hintText: '예: Galaxy, Nebula, Cluster',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _constellationController,
              decoration: const InputDecoration(
                labelText: '별자리',
                hintText: '예: Orion',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _magnitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '등급 (magnitude)',
                hintText: '예: 8.5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final number = int.parse(_numberController.text.trim());
      final name = _nameController.text.trim();
      final type = _typeController.text.trim();
      final constellation = _constellationController.text.trim();
      final magnitude = _magnitudeController.text.trim();

      final newObject = const CatalogMetadataEnricher().enrich(
        CatalogObject(
          id: _uuid.v4(),
          number: number,
          catalog: _selectedCatalog,
          name: name.isNotEmpty ? name : _selectedCatalog.label,
          type: type.isNotEmpty ? type : '-',
          constellation: constellation.isNotEmpty ? constellation : '-',
          ra: '',
          dec: '',
          magnitude: magnitude.isNotEmpty ? magnitude : '-',
        ),
      );

      await widget.catalogRepository.insert(newObject);

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => CatalogDetailViewModel(
              newObject,
              context.read<GalleryShootingRecordRepositoryAdapter>(),
              widget.catalogRepository,
              widget.registrationService,
              widget.metadataService,
              context.read<EquipmentRepository>(),
              context.read<EquipmentRecommendationService>(),
              context.read<BaseExposureSettingsService>(),
              context.read<ObjectImagingProfileProvider>(),
              context.read<ExposurePolicy>(),
              captureProjection: context
                  .read<CatalogCaptureProjectionService>(),
            ),
            child: const CatalogDetailScreen(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      setState(() => _isSaving = false);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}
