import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/equipment_tonight_group.dart';

/// 추천 장비 탭 — 장비 선택 Carousel(Swipe)만 담당.
class EquipmentRecommendationCarousel extends StatefulWidget {
  const EquipmentRecommendationCarousel({
    super.key,
    required this.groups,
    this.initialIndex = 0,
    this.onIndexChanged,
  });

  final List<EquipmentTonightGroup> groups;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<EquipmentRecommendationCarousel> createState() =>
      _EquipmentRecommendationCarouselState();
}

class _EquipmentRecommendationCarouselState
    extends State<EquipmentRecommendationCarousel> {
  static const _swipeHeight = 30.0;

  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex.clamp(
      0,
      widget.groups.isEmpty ? 0 : widget.groups.length - 1,
    );
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EquipmentRecommendationCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= widget.groups.length) {
      _currentPage = widget.groups.isEmpty ? 0 : widget.groups.length - 1;
    }
  }

  void _notifyIndex(int index) {
    setState(() => _currentPage = index);
    widget.onIndexChanged?.call(index);
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.groups.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: AppColors.textSecondary.withAlpha(40)),
        ),
        child: const Text(
          '오늘 추천할 장비 대상이 없습니다.\n관리자에서 장비를 등록했는지 확인해 주세요.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      );
    }

    final hasMultiple = widget.groups.length > 1;
    final canGoBack = _currentPage > 0;
    final canGoForward = _currentPage < widget.groups.length - 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingMd,
        AppTheme.spacingSm,
        AppTheme.spacingMd,
        AppTheme.spacingXs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.ic.withAlpha(60)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasMultiple)
                _SwipeChevron(
                  icon: Icons.chevron_left,
                  enabled: canGoBack,
                  onTap: canGoBack ? () => _goToPage(_currentPage - 1) : null,
                ),
              Expanded(
                child: SizedBox(
                  height: _swipeHeight,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.groups.length,
                    onPageChanged: _notifyIndex,
                    itemBuilder: (context, index) {
                      final item = widget.groups[index];
                      return Align(
                        alignment: hasMultiple
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: Text(
                          item.equipment.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                height: 1.2,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign:
                              hasMultiple ? TextAlign.center : TextAlign.left,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (hasMultiple)
                _SwipeChevron(
                  icon: Icons.chevron_right,
                  enabled: canGoForward,
                  onTap: canGoForward
                      ? () => _goToPage(_currentPage + 1)
                      : null,
                ),
            ],
          ),
          if (hasMultiple) ...[
            const SizedBox(height: 2),
            Text(
              '${_currentPage + 1} / ${widget.groups.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwipeChevron extends StatelessWidget {
  const _SwipeChevron({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.textSecondary
        : AppColors.textSecondary.withAlpha(80);

    return SizedBox(
      width: 22,
      height: _EquipmentRecommendationCarouselState._swipeHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
