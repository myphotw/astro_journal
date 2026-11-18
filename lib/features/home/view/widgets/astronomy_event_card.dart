import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/pc_design.dart';
import '../../../../data/models/astronomy_event.dart';
import '../../presentation/astronomy_event_presenter.dart';

class AstronomyEventCard extends StatelessWidget {
  const AstronomyEventCard({super.key, required this.event, required this.now});

  final AstronomyEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final category = AstronomyEventPresenter.categoryLabel(event.type);
    final countdown = AstronomyEventPresenter.countdownLabel(event, now);
    final tags = event.tags.take(2).toList(growable: false);
    final mobile = PcDesign.isMobileContent(context);
    final accent = mobile ? PcDesign.secondary : AppColors.messier;
    final muted = mobile ? PcDesign.muted : AppColors.textSecondary;
    final date = Text(
      AstronomyEventPresenter.dateLabel(event, now),
      maxLines: mobile ? null : 1,
      overflow: mobile ? null : TextOverflow.ellipsis,
      style: TextStyle(color: muted, fontSize: 12),
    );

    return Semantics(
      container: true,
      label: '$category, ${event.title}',
      child: Container(
        key: Key('astronomy-event-${event.id}'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: mobile ? PcDesign.raised : AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: mobile
                ? PcDesign.border
                : AppColors.textSecondary.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  AstronomyEventPresenter.categoryIcon(event.type),
                  size: 17,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              event.title,
              maxLines: mobile ? null : 2,
              overflow: mobile ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: mobile ? PcDesign.text : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingSm),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags.map((tag) => _EventTag(label: tag)).toList(),
              ),
            ],
            const SizedBox(height: AppTheme.spacingSm),
            if (mobile)
              Wrap(
                spacing: AppTheme.spacingSm,
                runSpacing: AppTheme.spacingXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  date,
                  if (countdown != null) _CountdownBadge(label: countdown),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: date),
                  if (countdown != null) ...[
                    const SizedBox(width: AppTheme.spacingSm),
                    _CountdownBadge(label: countdown),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EventTag extends StatelessWidget {
  const _EventTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final mobile = PcDesign.isMobileContent(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mobile
              ? PcDesign.card
              : AppColors.background.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mobile ? PcDesign.muted : AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = PcDesign.isMobileContent(context)
        ? PcDesign.secondary
        : AppColors.messier;
    return Container(
      key: Key('astronomy-event-countdown-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
