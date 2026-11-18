import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

enum PcPopupSize { small, medium, large, extraLarge }

Future<T?> showPcObservatoryDialog<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  PcPopupSize size = PcPopupSize.medium,
  bool scrollable = true,
  Widget? footer,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: 0.72),
  transitionDuration: const Duration(milliseconds: 170),
  pageBuilder: (dialogContext, _, _) => PcObservatoryDialog(
    title: title,
    size: size,
    scrollable: scrollable,
    footer: footer,
    child: child,
  ),
  transitionBuilder: (context, animation, _, child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curve),
        child: child,
      ),
    );
  },
);

class PcObservatoryDialog extends StatelessWidget {
  const PcObservatoryDialog({
    super.key,
    required this.title,
    required this.child,
    this.size = PcPopupSize.medium,
    this.scrollable = true,
    this.footer,
  });

  final String title;
  final Widget child;
  final PcPopupSize size;
  final bool scrollable;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final widthRatio = switch (size) {
      PcPopupSize.small => 0.55,
      PcPopupSize.medium => 0.78,
      PcPopupSize.large => 0.86,
      PcPopupSize.extraLarge => 0.90,
    };
    final heightRatio = switch (size) {
      PcPopupSize.small => 0.42,
      PcPopupSize.medium => 0.72,
      PcPopupSize.large => 0.82,
      PcPopupSize.extraLarge => 0.85,
    };
    final maxWidth = switch (size) {
      PcPopupSize.small => 440.0,
      PcPopupSize.medium => 820.0,
      PcPopupSize.large => 1600.0,
      PcPopupSize.extraLarge => 1800.0,
    };
    final maxHeight = switch (size) {
      PcPopupSize.small => 320.0,
      PcPopupSize.medium => 700.0,
      PcPopupSize.large => 860.0,
      PcPopupSize.extraLarge => 940.0,
    };
    final availableWidth = (screen.width - 2 * AppTheme.spacingLg)
        .clamp(0.0, double.infinity).toDouble();
    final availableHeight = (screen.height - 2 * AppTheme.spacingLg)
        .clamp(0.0, double.infinity).toDouble();
    final desiredWidth = (screen.width * widthRatio)
        .clamp(0.0, availableWidth < maxWidth ? availableWidth : maxWidth)
        .toDouble();
    final desiredHeight = (screen.height * heightRatio)
        .clamp(0.0, availableHeight < maxHeight ? availableHeight : maxHeight)
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(AppTheme.spacingLg),
      backgroundColor: AppColors.observatorySurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: const BorderSide(color: AppColors.observatoryBorder),
      ),
      child: SizedBox(
        width: desiredWidth,
        height: desiredHeight,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
            child: Row(children: [
              Expanded(child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.observatoryText,
                    fontWeight: FontWeight.w700,
                  ))),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.observatoryBorder),
          Expanded(
            child: scrollable
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTheme.spacingXl),
                    child: child,
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    child: child,
                  ),
          ),
          if (footer != null) ...[
            const Divider(height: 1, color: AppColors.observatoryBorder),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: footer!,
            ),
          ],
        ]),
      ),
    );
  }
}
