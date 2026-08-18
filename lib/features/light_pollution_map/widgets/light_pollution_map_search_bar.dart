import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/observation_site.dart';
import '../../../services/geocoding_service.dart';
import '../viewmodel/light_pollution_map_view_model.dart';
import 'light_pollution_favorites_dropdown.dart';

class LightPollutionMapSearchBar extends StatefulWidget {
  const LightPollutionMapSearchBar({super.key, this.onFavoriteSelected});

  final Future<void> Function(ObservationSite favorite)? onFavoriteSelected;

  @override
  State<LightPollutionMapSearchBar> createState() =>
      _LightPollutionMapSearchBarState();
}

class _LightPollutionMapSearchBarState
    extends State<LightPollutionMapSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _suppressSearch = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted || _suppressSearch) return;
    context.read<LightPollutionMapViewModel>().onSearchQueryChanged(
      _controller.text,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(LightPollutionMapViewModel vm) async {
    await vm.searchAddress(_controller.text);
  }

  void _clear(LightPollutionMapViewModel vm) {
    _suppressSearch = true;
    _controller.clear();
    _suppressSearch = false;
    vm.clearSearchSuggestions();
    _focusNode.requestFocus();
  }

  void _selectSuggestion(
    LightPollutionMapViewModel vm,
    LocationSearchSuggestion suggestion,
  ) {
    _suppressSearch = true;
    _controller.text = suggestion.mainText;
    _suppressSearch = false;
    _focusNode.unfocus();
    vm.selectSearchSuggestion(suggestion);
  }

  Future<bool> _confirmDeleteFavorite(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('즐겨찾기 삭제'),
        content: const Text('즐겨찾기를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LightPollutionMapViewModel>();
    final surface = Theme.of(context).colorScheme.surface;
    final query = _controller.text.trim();
    final showSuggestions =
        !vm.isFavoritesDropdownOpen &&
        query.length >= 2 &&
        (vm.isSearching ||
            vm.searchSuggestions.isNotEmpty ||
            vm.searchErrorMessage != null);
    final showFavorites = vm.isFavoritesDropdownOpen;
    final hasText = _controller.text.isNotEmpty;

    return Material(
      color: surface.withValues(alpha: 0.96),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingSm,
              vertical: 4,
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: '지역명 검색',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingSm,
                        vertical: 10,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(vm),
                  ),
                ),
                if (vm.isSearching)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (hasText)
                  IconButton(
                    tooltip: '지우기',
                    icon: const Icon(Icons.clear, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () => _clear(vm),
                  ),
                IconButton(
                  tooltip: '즐겨찾기',
                  icon: Icon(
                    vm.isFavoritesDropdownOpen ? Icons.star : Icons.star_border,
                    size: 20,
                  ),
                  color: vm.isFavoritesDropdownOpen
                      ? AppColors.solar
                      : AppColors.textSecondary,
                  onPressed: () async {
                    _focusNode.unfocus();
                    await vm.toggleFavoritesDropdown();
                  },
                ),
              ],
            ),
          ),
          if (showFavorites) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.surface),
            LightPollutionFavoritesDropdown(
              viewModel: vm,
              onSelect: (summary) async {
                _focusNode.unfocus();
                final handler = widget.onFavoriteSelected;
                if (handler != null) {
                  await handler(summary.favorite);
                } else {
                  await vm.selectFavorite(summary.favorite);
                }
              },
              onUnfavorite: (summary) async {
                final confirmed = await _confirmDeleteFavorite(context);
                if (!confirmed || !context.mounted) return;
                await vm.removeFavoriteAt(
                  summary.favorite.latitude,
                  summary.favorite.longitude,
                );
              },
            ),
          ],
          if (showSuggestions) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.surface),
            if (vm.searchSuggestions.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: vm.searchSuggestions.length >= 5 ? 260 : 220,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: vm.searchSuggestions.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.surface,
                  ),
                  itemBuilder: (context, index) {
                    final suggestion = vm.searchSuggestions[index];
                    return _SearchSuggestionTile(
                      suggestion: suggestion,
                      onTap: () => _selectSuggestion(vm, suggestion),
                    );
                  },
                ),
              )
            else if (vm.searchErrorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingSm,
                  10,
                  AppTheme.spacingSm,
                  12,
                ),
                child: Text(
                  vm.searchErrorMessage!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SearchSuggestionTile extends StatelessWidget {
  const _SearchSuggestionTile({required this.suggestion, required this.onTap});

  final LocationSearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingSm,
            vertical: 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.solar,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.mainText,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    if (suggestion.secondaryText != null &&
                        suggestion.secondaryText!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        suggestion.secondaryText!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
