import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/app_navigation_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalog_object.dart';

/// 홈·카탈로그에서 성도로 이동해 천체 위치를 보여주는 버튼.
class SkyMapLocationButton extends StatelessWidget {
  const SkyMapLocationButton({
    super.key,
    required this.object,
    this.popBeforeNavigate = true,
    this.expanded = true,
  });

  final CatalogObject object;
  final bool popBeforeNavigate;
  final bool expanded;

  void _onPressed(BuildContext context) {
    if (popBeforeNavigate && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    context.read<AppNavigationNotifier>().navigateToSkyMap(object);
  }

  @override
  Widget build(BuildContext context) {
    final child = OutlinedButton.icon(
      onPressed: () => _onPressed(context),
      icon: const Icon(Icons.travel_explore, size: 18),
      label: const Text('위치보기'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.messier,
        side: BorderSide(color: AppColors.messier.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
    if (!expanded) return child;
    return SizedBox(width: double.infinity, child: child);
  }
}
