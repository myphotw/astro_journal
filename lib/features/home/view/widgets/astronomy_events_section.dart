import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../viewmodel/astronomy_events_view_model.dart';
import '../astronomy_events_screen.dart';
import 'astronomy_event_card.dart';

class AstronomyEventsSection extends StatefulWidget {
  const AstronomyEventsSection({super.key});

  @override
  State<AstronomyEventsSection> createState() => _AstronomyEventsSectionState();
}

class _AstronomyEventsSectionState extends State<AstronomyEventsSection> {
  AstronomyEventsViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextViewModel = context.read<AstronomyEventsViewModel?>();
    if (identical(_viewModel, nextViewModel)) return;
    _viewModel = nextViewModel;
    if (nextViewModel != null && !nextViewModel.hasLoaded) {
      scheduleMicrotask(() => nextViewModel.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AstronomyEventsViewModel?>();
    if (viewModel == null) return const SizedBox.shrink();

    return Column(
      key: const Key('home-astronomy-events-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '다가오는 천문 이벤트',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              key: const Key('open-all-astronomy-events'),
              onPressed: () => AstronomyEventsScreen.open(context),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('전체보기 >', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingSm),
        _HomeEventsBody(viewModel: viewModel),
      ],
    );
  }
}

class _HomeEventsBody extends StatelessWidget {
  const _HomeEventsBody({required this.viewModel});

  final AstronomyEventsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading && viewModel.events.isEmpty) {
      return const SizedBox(
        key: Key('astronomy-events-loading'),
        height: 88,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (viewModel.errorMessage != null && viewModel.events.isEmpty) {
      return _SectionMessage(
        key: const Key('astronomy-events-error'),
        message: viewModel.errorMessage!,
        actionLabel: '다시 시도',
        onAction: viewModel.refresh,
      );
    }
    if (viewModel.events.isEmpty) {
      return const _SectionMessage(
        key: Key('astronomy-events-empty'),
        message: '예정된 주요 천문 이벤트가 없습니다.',
      );
    }

    final now = DateTime.now();
    final events = viewModel.homeEvents;
    return LayoutBuilder(
      builder: (context, constraints) {
        const preferredCardWidth = 230.0;
        final columns = math.max(
          1,
          (constraints.maxWidth / preferredCardWidth).floor(),
        );
        final spacing = AppTheme.spacingSm * (columns - 1);
        final cardWidth = (constraints.maxWidth - spacing) / columns;
        return Wrap(
          spacing: AppTheme.spacingSm,
          runSpacing: AppTheme.spacingSm,
          children: [
            for (final event in events)
              SizedBox(
                width: cardWidth,
                child: AstronomyEventCard(event: event, now: now),
              ),
          ],
        );
      },
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
