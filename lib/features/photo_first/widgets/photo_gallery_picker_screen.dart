import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/gallery_permission_service.dart';

/// 앱 내 갤러리 선택 바텀시트. 폴더 선택·다중 선택·닫기를 제공한다.
class PhotoGalleryPicker {
  PhotoGalleryPicker._();

  static Future<List<File>> pick(BuildContext context) async {
    final result = await showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const PhotoGalleryPickerSheet(),
    );
    return result ?? [];
  }
}

class PhotoGalleryPickerSheet extends StatefulWidget {
  const PhotoGalleryPickerSheet({super.key});

  @override
  State<PhotoGalleryPickerSheet> createState() => _PhotoGalleryPickerSheetState();
}

class _PhotoGalleryPickerSheetState extends State<PhotoGalleryPickerSheet> {
  final _selectedIds = <String>{};
  final _scrollController = ScrollController();

  static final _newestFirstFilter = FilterOptionGroup(
    orders: [
      const OrderOption(type: OrderOptionType.createDate, asc: false),
    ],
  );

  List<AssetPathEntity> _albums = [];
  List<AssetEntity> _assets = [];
  AssetPathEntity? _album;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  bool _openSettingsOnError = false;
  int _page = 0;
  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final access = await GalleryPermissionService.ensurePhotoAccess();
    if (!mounted) return;

    if (access != GalleryAccessResult.granted) {
      setState(() {
        _isLoading = false;
        _openSettingsOnError = access == GalleryAccessResult.permanentlyDenied;
        _errorMessage = _openSettingsOnError
            ? '설정에서 사진 접근 권한을 허용해 주세요.'
            : '갤러리 접근 권한이 필요합니다.';
      });
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      onlyAll: false,
      filterOption: _newestFirstFilter,
    );
    if (albums.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '갤러리에 사진이 없습니다.';
      });
      return;
    }

    _albums = albums;
    await _loadAlbum(albums.first);
  }

  Future<void> _loadAlbum(AssetPathEntity album) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _album = album;
      _page = 0;
      _hasMore = true;
      _assets = [];
    });

    final assets = await album.getAssetListPaged(page: 0, size: _pageSize);

    if (!mounted) return;
    setState(() {
      _assets = assets;
      _isLoading = false;
      _hasMore = assets.length >= _pageSize;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    if (_album?.id == album.id) return;
    _selectedIds.clear();
    await _loadAlbum(album);
  }

  Future<void> _showAlbumPicker() async {
    if (_albums.isEmpty) return;

    final selected = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppTheme.spacingMd,
                AppTheme.spacingMd,
                AppTheme.spacingMd,
                AppTheme.spacingSm,
              ),
              child: Text(
                '앨범 선택',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  final isSelected = _album?.id == album.id;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.folder : Icons.folder_outlined,
                      color: isSelected ? AppColors.solar : AppColors.textSecondary,
                    ),
                    title: Text(
                      album.name,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.solar, size: 20)
                        : null,
                    onTap: () => Navigator.of(context).pop(album),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null && mounted) {
      await _switchAlbum(selected);
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _album == null) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 240) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_album == null || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _page + 1;
    final assets = await _album!.getAssetListPaged(
      page: nextPage,
      size: _pageSize,
    );

    if (!mounted) return;
    setState(() {
      _page = nextPage;
      _assets = [..._assets, ...assets];
      _hasMore = assets.length >= _pageSize;
      _isLoadingMore = false;
    });
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedIds.isEmpty) return;

    final selected = _assets.where((a) => _selectedIds.contains(a.id));
    final files = <File>[];
    for (final asset in selected) {
      final file = await asset.originFile ?? await asset.file;
      if (file != null) files.add(file);
    }

    if (!mounted) return;
    Navigator.of(context).pop(files);
  }

  void _close() => Navigator.of(context).pop(<File>[]);

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.55;

    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMd,
                AppTheme.spacingSm,
                AppTheme.spacingSm,
                AppTheme.spacingXs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedIds.isEmpty
                          ? '사진 선택'
                          : '사진 선택 (${_selectedIds.length})',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedIds.isEmpty ? null : _confirmSelection,
                    child: const Text('완료'),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                    onPressed: _close,
                  ),
                ],
              ),
            ),
            if (_album != null && _errorMessage == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingMd,
                  0,
                  AppTheme.spacingMd,
                  AppTheme.spacingXs,
                ),
                child: InkWell(
                  onTap: _showAlbumPicker,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingSm,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                      border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: AppColors.solar,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _album!.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Divider(height: 1, color: AppColors.surface),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              if (_openSettingsOnError)
                FilledButton(
                  onPressed: openAppSettings,
                  child: const Text('설정 열기'),
                )
              else
                OutlinedButton(
                  onPressed: _loadInitial,
                  child: const Text('다시 시도'),
                ),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return const Center(
        child: Text(
          '표시할 사진이 없습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _assets.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final asset = _assets[index];
        final selected = _selectedIds.contains(asset.id);

        return GestureDetector(
          onTap: () => _toggleSelection(asset),
          onLongPress: () => _openPreview(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AssetThumbnail(asset: asset),
              if (selected)
                Container(
                  color: AppColors.solar.withValues(alpha: 0.35),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.solar : Colors.white70,
                  size: 22,
                ),
              ),
              Positioned(
                bottom: 4,
                left: 4,
                child: _PreviewButton(onTap: () => _openPreview(index)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 선택한 사진의 미리보기 화면을 연다. 미리보기 내에서도 선택/해제가
  /// 가능하며, 닫을 때 그리드의 선택 상태를 갱신한다.
  /// 미리보기에서 [완료]를 누르면 선택 확정 후 바텀시트까지 닫는다.
  Future<void> _openPreview(int index) async {
    final result = await Navigator.of(context).push<_PreviewExit>(
      MaterialPageRoute(
        builder: (_) => _PhotoPreviewViewer(
          assets: _assets,
          initialIndex: index,
          initialSelectedIds: _selectedIds,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedIds
        ..clear()
        ..addAll(result.selectedIds);
    });

    if (result.confirm) {
      await _confirmSelection();
    }
  }
}

/// 전체보기 종료 결과. [confirm]이 true면 바텀시트 선택도 확정한다.
class _PreviewExit {
  const _PreviewExit({
    required this.selectedIds,
    required this.confirm,
  });

  final Set<String> selectedIds;
  final bool confirm;
}

/// 썸네일 위에 표시되는 미리보기 진입 버튼.
class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.zoom_in,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// 선택 전 사진을 원본 크기로 확인할 수 있는 전체화면 미리보기.
///
/// 좌우 스와이프로 다른 사진을 넘겨볼 수 있고, 하단 버튼으로 현재 사진의
/// 선택 여부를 바로 토글할 수 있다. 닫을 때 최종 선택 상태를 반환한다.
class _PhotoPreviewViewer extends StatefulWidget {
  const _PhotoPreviewViewer({
    required this.assets,
    required this.initialIndex,
    required this.initialSelectedIds,
  });

  final List<AssetEntity> assets;
  final int initialIndex;
  final Set<String> initialSelectedIds;

  @override
  State<_PhotoPreviewViewer> createState() => _PhotoPreviewViewerState();
}

class _PhotoPreviewViewerState extends State<_PhotoPreviewViewer> {
  late final PageController _pageController;
  late final Set<String> _selectedIds;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _selectedIds = {...widget.initialSelectedIds};
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleCurrent() {
    final asset = widget.assets[_currentIndex];
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  void _close() => Navigator.of(context).pop(
        _PreviewExit(selectedIds: _selectedIds, confirm: false),
      );

  void _confirm() {
    if (_selectedIds.isEmpty) return;
    Navigator.of(context).pop(
      _PreviewExit(selectedIds: _selectedIds, confirm: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.assets.length;
    final selected = _selectedIds.contains(widget.assets[_currentIndex].id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
        title: Text(
          '${_currentIndex + 1} / $total',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty ? null : _confirm,
            child: Text(
              '완료',
              style: TextStyle(
                color: _selectedIds.isEmpty
                    ? Colors.white38
                    : AppColors.solar,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: total,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return _PreviewPage(asset: widget.assets[index]);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingLg,
            AppTheme.spacingSm,
            AppTheme.spacingLg,
            AppTheme.spacingMd,
          ),
          child: FilledButton.icon(
            onPressed: _toggleCurrent,
            style: FilledButton.styleFrom(
              backgroundColor: selected ? AppColors.solar : AppColors.surface,
              foregroundColor: selected ? Colors.black : Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
            label: Text(selected ? '선택됨 · 해제' : '이 사진 선택'),
          ),
        ),
      ),
    );
  }
}

/// 미리보기 1페이지 — 원본에 가까운 화질로 로드하고, 확대·축소를 지원한다.
class _PreviewPage extends StatelessWidget {
  const _PreviewPage({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: asset.file,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.solar),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
          );
        }
        final screen = MediaQuery.sizeOf(context);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cachePx = (screen.longestSide * dpr).round().clamp(720, 2048);
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.file(
              file,
              fit: BoxFit.contain,
              cacheWidth: cachePx,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _AssetThumbnail extends StatefulWidget {
  const _AssetThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  static final Map<String, Future<Uint8List?>> _futureCache = {};
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    final id = widget.asset.id;
    _future = _futureCache.putIfAbsent(
      id,
      () => widget.asset.thumbnailDataWithSize(
        const ThumbnailSize.square(300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }
        return const ColoredBox(
          color: AppColors.surface,
          child: Center(
            child: Icon(Icons.image_outlined, color: AppColors.textSecondary),
          ),
        );
      },
    );
  }
}
