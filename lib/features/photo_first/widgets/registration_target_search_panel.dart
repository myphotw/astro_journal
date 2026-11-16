import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/catalog_object.dart';
import '../../../services/catalog_search_service.dart';

/// 위저드 Step1용 인라인 대상 검색 (별도 SearchDelegate push 없음).
class RegistrationTargetSearchPanel extends StatefulWidget {
  const RegistrationTargetSearchPanel({
    super.key,
    required this.allObjects,
    required this.onSelected,
    this.selected,
    this.hintText = '촬영 대상 검색 (M, NGC, IC, Sh2 등)',
    this.embedded = false,
  });

  final List<CatalogObject> allObjects;
  final CatalogObject? selected;
  final ValueChanged<CatalogObject> onSelected;
  final String hintText;

  /// Search results float above the shared form instead of changing its height.
  final bool embedded;

  @override
  State<RegistrationTargetSearchPanel> createState() =>
      _RegistrationTargetSearchPanelState();
}

class _RegistrationTargetSearchPanelState
    extends State<RegistrationTargetSearchPanel> {
  final _controller = TextEditingController();
  final _searchService = CatalogSearchService();
  final _menuController = MenuController();
  Timer? _timer;
  List<CatalogObject> _results = const [];
  var _searching = false;

  @override
  void initState() {
    super.initState();
    _searchService.ensureIndex(widget.allObjects);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showEmbeddedResults() {
    if (!widget.embedded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _controller.text.trim().isNotEmpty &&
          !_menuController.isOpen) {
        _menuController.open();
      }
    });
  }

  void _onQueryChanged(String raw) {
    final q = raw.trim();
    _timer?.cancel();
    if (q.isEmpty) {
      if (widget.embedded && _menuController.isOpen) _menuController.close();
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _showEmbeddedResults();
    _timer = Timer(const Duration(milliseconds: 180), () {
      final found = _searchService.search(q, widget.allObjects);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
      _showEmbeddedResults();
    });
  }

  void _selectTarget(CatalogObject object) {
    _timer?.cancel();
    if (widget.embedded && _menuController.isOpen) _menuController.close();
    _controller.clear();
    setState(() {
      _results = const [];
      _searching = false;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onSelected(
      CatalogSearchService.resolvePrimaryFromList(object, widget.allObjects),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null) ...[
          _SelectedTargetBanner(object: selected, compact: widget.embedded),
          SizedBox(
            height: widget.embedded ? AppTheme.spacingSm : AppTheme.spacingMd,
          ),
        ],
        if (widget.embedded)
          LayoutBuilder(
            builder: (context, constraints) => MenuAnchor(
              controller: _menuController,
              useRootOverlay: true,
              crossAxisUnconstrained: false,
              style: MenuStyle(
                alignment: AlignmentDirectional.bottomStart,
                fixedSize: WidgetStatePropertyAll(
                  Size.fromWidth(constraints.maxWidth),
                ),
                maximumSize: WidgetStatePropertyAll(
                  Size(constraints.maxWidth, 240),
                ),
              ),
              menuChildren: _embeddedMenuItems(selected),
              child: _buildSearchField(),
            ),
          )
        else
          _buildSearchField(),
        if (!widget.embedded) ...[
          const SizedBox(height: AppTheme.spacingSm),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_results.isNotEmpty)
            Expanded(child: _buildResults(selected))
          else if (_controller.text.trim().isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '검색 결과가 없습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Text(
                  '천체명·카탈로그 번호로 검색하세요.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildSearchField() => TextField(
    controller: _controller,
    onChanged: _onQueryChanged,
    decoration: InputDecoration(
      labelText: '대상 검색',
      hintText: widget.hintText,
      prefixIcon: const Icon(Icons.search),
      border: const OutlineInputBorder(),
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
    ),
  );

  List<Widget> _embeddedMenuItems(CatalogObject? selected) {
    if (_searching) {
      return const [MenuItemButton(onPressed: null, child: Text('검색 중…'))];
    }
    if (_results.isEmpty) {
      return const [
        MenuItemButton(onPressed: null, child: Text('검색 결과가 없습니다.')),
      ];
    }
    return [
      for (final object in _results)
        MenuItemButton(
          onPressed: () => _selectTarget(object),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      object.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      object.displayCommonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected?.id == object.id)
                const Icon(Icons.check_circle, size: 18),
            ],
          ),
        ),
    ];
  }

  Widget _buildResults(CatalogObject? selected) => ListView.separated(
    itemCount: _results.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, index) {
      final obj = _results[index];
      final isSelected = selected?.id == obj.id;
      return ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: obj.catalog.accentColor.withAlpha(28),
        title: Text(
          obj.displayName,
          style: TextStyle(
            color: obj.catalog.accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          obj.displayCommonName,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: obj.catalog.accentColor)
            : null,
        onTap: () => _selectTarget(obj),
      );
    },
  );
}

class _SelectedTargetBanner extends StatelessWidget {
  const _SelectedTargetBanner({required this.object, this.compact = false});

  final CatalogObject object;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = object.catalog.accentColor;
    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: color.withAlpha(102)),
        ),
        child: Row(
          children: [
            Text(
              object.catalog.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppTheme.spacingSm),
            Expanded(
              child: Text(
                object.displayCommonName.trim().isEmpty
                    ? object.displayName
                    : '${object.displayName} · ${object.displayCommonName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withAlpha(64), color.withAlpha(20)],
        ),
        border: Border.all(color: color.withAlpha(102)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(51),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              object.catalog.label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            object.displayName,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            object.displayCommonName,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
