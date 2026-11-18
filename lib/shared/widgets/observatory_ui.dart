import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Shared, code-based surfaces for the observatory UI. No asset is baked in.
class ObservatoryPanel extends StatelessWidget {
  const ObservatoryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.spacingLg),
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: backgroundColor ?? AppColors.observatorySurface,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      border: Border.all(color: borderColor ?? AppColors.observatoryBorder),
    ),
    child: child,
  );
}

class ObservatorySectionHeader extends StatelessWidget {
  const ObservatorySectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
    this.iconColor,
    this.titleColor,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19,
          color: iconColor ?? AppColors.observatoryAccent),
      const SizedBox(width: AppTheme.spacingSm),
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: titleColor ?? AppColors.observatoryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      ?trailing,
    ],
  );
}

class ObservatoryButton extends StatelessWidget {
  const ObservatoryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(
        foregroundColor ?? AppColors.observatoryText,
      ),
      backgroundColor: WidgetStatePropertyAll(
        backgroundColor ?? (primary
            ? AppColors.observatoryPrimary : AppColors.observatorySurfaceRaised),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: borderColor ?? (primary
              ? AppColors.observatoryPrimary
              : AppColors.observatoryBorder),
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return TextButton(onPressed: onPressed, style: style, child: Text(label));
  }
}

class ObservatoryIconButton extends StatelessWidget {
  const ObservatoryIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    color: AppColors.observatoryText,
    style: IconButton.styleFrom(
      backgroundColor: AppColors.observatorySurfaceRaised,
      side: const BorderSide(color: AppColors.observatoryBorder),
    ),
  );
}

class ObservatoryStatusBadge extends StatelessWidget {
  const ObservatoryStatusBadge({
    super.key,
    required this.label,
    this.color = AppColors.observatoryAccent,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.38)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11),
    ),
  );
}

class ObservatoryInput extends StatelessWidget {
  const ObservatoryInput({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.search = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool search;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: const TextStyle(color: AppColors.observatoryText),
    decoration: ObservatoryFieldStyle.decoration(
      label: label,
      hint: hint,
      icon: search ? Icons.search : null,
    ),
  );
}

class ObservatoryFieldStyle {
  ObservatoryFieldStyle._();

  static InputDecoration decoration({
    required String label,
    String? hint,
    IconData? icon,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: AppColors.observatorySurfaceRaised,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.observatoryBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.observatoryBorder),
    ),
  );
}

class ObservatoryDropdown<T> extends StatelessWidget {
  const ObservatoryDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    items: items,
    onChanged: onChanged,
    dropdownColor: AppColors.observatorySurfaceRaised,
    decoration: ObservatoryFieldStyle.decoration(label: label),
  );
}

class ObservatoryDialog extends StatelessWidget {
  const ObservatoryDialog({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.observatorySurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.spacingMd),
          child,
        ],
      ),
    ),
  );
}

class ObservatoryBottomSheet extends StatelessWidget {
  const ObservatoryBottomSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      decoration: const BoxDecoration(
        color: AppColors.observatorySurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: child,
    ),
  );
}

class ObservatoryStateView extends StatelessWidget {
  const ObservatoryStateView({
    super.key,
    required this.message,
    this.loading = false,
    this.action,
  });

  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppTheme.spacingLg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) const CircularProgressIndicator(strokeWidth: 2),
        if (loading) const SizedBox(height: AppTheme.spacingSm),
        Text(message, style: const TextStyle(color: AppColors.observatoryMuted)),
        if (action != null) ...[
          const SizedBox(height: AppTheme.spacingMd),
          action!,
        ],
      ],
    ),
  );
}
