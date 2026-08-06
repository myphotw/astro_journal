import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/catalog_type.dart';
import '../core/formatters/catalog_object_display_formatter.dart';
import '../core/theme/app_colors.dart';
import '../data/models/catalog_object.dart';
import '../services/catalog_search_service.dart';

/// 카탈로그 전체 천체 통합 검색 Delegate.
class CatalogTargetSearchDelegate extends SearchDelegate<CatalogObject?> {
  CatalogTargetSearchDelegate({
    required this.allObjects,
    CatalogSearchService? searchService,
    this.hintText = '천체 검색 (예: M27, Dumbbell, NGC 6853, Sh2-155)',
  }) : _searchService = searchService ?? CatalogSearchService() {
    // 검색 UI 진입 전 인덱스 워밍 — 첫 키입력 버벅임 방지
    _searchService.ensureIndex(allObjects);
  }

  final List<CatalogObject> allObjects;
  final CatalogSearchService _searchService;
  final String hintText;

  @override
  String get searchFieldLabel => hintText;

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: '닫기',
          onPressed: () => close(context, null),
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _DebouncedCatalogSearchList(
        query: query,
        allObjects: allObjects,
        searchService: _searchService,
        onSelect: (obj) => close(
          context,
          CatalogSearchService.resolvePrimaryFromList(obj, allObjects),
        ),
      );

  @override
  Widget buildSuggestions(BuildContext context) => _DebouncedCatalogSearchList(
        query: query,
        allObjects: allObjects,
        searchService: _searchService,
        onSelect: (obj) => close(
          context,
          CatalogSearchService.resolvePrimaryFromList(obj, allObjects),
        ),
      );
}

/// 키입력마다 전체 검색하지 않도록 디바운스.
class _DebouncedCatalogSearchList extends StatefulWidget {
  const _DebouncedCatalogSearchList({
    required this.query,
    required this.allObjects,
    required this.searchService,
    required this.onSelect,
  });

  final String query;
  final List<CatalogObject> allObjects;
  final CatalogSearchService searchService;
  final ValueChanged<CatalogObject> onSelect;

  @override
  State<_DebouncedCatalogSearchList> createState() =>
      _DebouncedCatalogSearchListState();
}

class _DebouncedCatalogSearchListState
    extends State<_DebouncedCatalogSearchList> {
  Timer? _timer;
  String _activeQuery = '';
  List<CatalogObject> _results = const [];
  var _searching = false;

  @override
  void initState() {
    super.initState();
    _schedule(widget.query);
  }

  @override
  void didUpdateWidget(covariant _DebouncedCatalogSearchList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _schedule(widget.query);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(String raw) {
    final q = raw.trim();
    _timer?.cancel();
    if (q.isEmpty) {
      setState(() {
        _activeQuery = '';
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _timer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final results = widget.searchService.search(q, widget.allObjects);
      setState(() {
        _activeQuery = q;
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.trim().isEmpty) {
      return const Center(
        child: Text(
          '천체명 또는 번호를 입력하세요',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (_searching && _activeQuery != widget.query.trim()) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          '검색 결과가 없습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final obj = _results[index];
        return ListTile(
          leading: _CatalogBadge(catalog: obj.catalog),
          title: Text(
            CatalogObjectDisplayFormatter.catalogTitle(obj),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            CatalogObjectDisplayFormatter.listSubtitle(obj),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onSelect(obj),
        );
      },
    );
  }
}

class _CatalogBadge extends StatelessWidget {
  const _CatalogBadge({required this.catalog});

  final CatalogType catalog;

  Color get _color => catalog.accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withAlpha(51),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        catalog.label,
        style: TextStyle(color: _color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
