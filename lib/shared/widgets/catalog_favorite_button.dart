import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/catalog_favorite_controller.dart';

class CatalogFavoriteButton extends StatelessWidget {
  const CatalogFavoriteButton({
    super.key,
    required this.catalogObjectId,
    this.color,
  });

  final String catalogObjectId;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    late final CatalogFavoriteController controller;
    try {
      controller = context.watch<CatalogFavoriteController>();
    } on ProviderNotFoundException {
      // Isolated legacy widget tests may not install the app-level provider.
      return const SizedBox.shrink();
    }
    final favorite = controller.isFavorite(catalogObjectId);
    final pending = controller.isPending(catalogObjectId);
    return IconButton(
      key: ValueKey('catalog-favorite-$catalogObjectId'),
      tooltip: favorite ? '즐겨찾기 해제' : '즐겨찾기 등록',
      onPressed: pending
          ? null
          : () async {
              try {
                await controller.toggle(catalogObjectId);
              } on CatalogFavoriteActionException catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.message)));
              }
            },
      icon: pending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: favorite ? (color ?? Colors.amber) : color,
            ),
    );
  }
}
