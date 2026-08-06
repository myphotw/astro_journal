import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/catalog_type.dart';
import '../../core/formatters/catalog_object_display_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/catalog_object.dart';
import '../../services/catalog_search_index.dart';
import '../../services/catalog_search_service.dart';

/// 검색창 하단 인라인 천체 검색 결과 (카탈로그·갤러리 공통).
class InlineCatalogSearchResults extends StatefulWidget {
  const InlineCatalogSearchResults({
    super.key,
    required this.query,
    required this.allObjects,
    required this.onObjectSelected,
    this.searchIndex,
    this.searchService,
    this.emptyHint = '천체명 또는 번호를 입력하세요',
    this.debounceDuration = const Duration(milliseconds: 180),
  });

  final String query;
  final List<CatalogObject> allObjects;
  final ValueChanged<CatalogObject> onObjectSelected;
  final CatalogSearchIndex? searchIndex;
  final CatalogSearchService? searchService;
  final String emptyHint;
  final Duration debounceDuration;

  @override
  State<InlineCatalogSearchResults> createState() =>
      _InlineCatalogSearchResultsState();
}

class _InlineCatalogSearchResultsState extends State<InlineCatalogSearchResults> {
  Timer? _debounceTimer;
  String _debouncedQuery = '';
  List<CatalogObject> _results = const [];

  @override
  void initState() {
    super.initState();
    _scheduleSearch(widget.query);
  }

  @override
  void didUpdateWidget(covariant InlineCatalogSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.searchIndex != widget.searchIndex ||
        oldWidget.allObjects != widget.allObjects) {
      _scheduleSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _scheduleSearch(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (!mounted) {
        return;
      }
      final trimmed = query.trim();
      if (trimmed.isEmpty) {
        setState(() {
          _debouncedQuery = '';
          _results = const [];
        });
        return;
      }

      final service = widget.searchService ?? CatalogSearchService();
      final results = service.search(
        trimmed,
        widget.allObjects,
        index: widget.searchIndex,
      );

      setState(() {
        _debouncedQuery = trimmed;
        _results = results;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_debouncedQuery.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingSm,
        ),
        child: Text(
          widget.emptyHint,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingSm,
        ),
        child: Text(
          '검색 결과가 없습니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.35;

    return Material(
      color: AppColors.surface,
      elevation: 2,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight.clamp(120, 320)),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXs),
          itemCount: _results.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final obj = _results[index];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: _CatalogSearchBadge(catalog: obj.catalog),
              title: Text(
                CatalogObjectDisplayFormatter.catalogTitle(obj),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                CatalogObjectDisplayFormatter.listSubtitle(obj),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => widget.onObjectSelected(obj),
            );
          },
        ),
      ),
    );
  }
}

class _CatalogSearchBadge extends StatelessWidget {
  const _CatalogSearchBadge({required this.catalog});

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
        style: TextStyle(
          color: _color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
