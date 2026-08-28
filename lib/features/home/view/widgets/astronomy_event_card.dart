import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
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

    return Semantics(
      container: true,
      label: '$category, ${event.title}',
      child: Container(
        key: Key('astronomy-event-${event.id}'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: AppColors.textSecondary.withValues(alpha: 0.18),
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
                  color: AppColors.messier,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.messier,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    AstronomyEventPresenter.dateLabel(event, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
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
    return Container(
      key: Key('astronomy-event-countdown-$label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.messier.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.messier,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
