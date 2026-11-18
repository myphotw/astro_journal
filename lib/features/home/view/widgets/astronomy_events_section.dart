import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pc_scroll_edge_buttons.dart';
import '../../presentation/astronomy_event_presenter.dart';
import '../../viewmodel/astronomy_events_view_model.dart';
import '../astronomy_events_screen.dart';
import 'astronomy_event_card.dart';
import 'pc_home_colors.dart';

class AstronomyEventsSection extends StatefulWidget {
  const AstronomyEventsSection({super.key, this.compactList = false});

  final bool compactList;

  @override
  State<AstronomyEventsSection> createState() => _AstronomyEventsSectionState();
}

class _AstronomyEventsSectionState extends State<AstronomyEventsSection> {
  AstronomyEventsViewModel? _viewModel;
  final ScrollController _eventScrollController = ScrollController();

  @override
  void dispose() {
    _eventScrollController.dispose();
    super.dispose();
  }

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
                  color: widget.compactList
                      ? PcHomeColors.text : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (widget.compactList)
              PcScrollEdgeButtons(controller: _eventScrollController),
            TextButton(
              key: const Key('open-all-astronomy-events'),
              onPressed: () => AstronomyEventsScreen.open(
                context, showHomeNavigation: widget.compactList,
              ),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('전체보기 >', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        SizedBox(height: widget.compactList ? 4 : AppTheme.spacingSm),
        if (widget.compactList)
          Expanded(child: _HomeEventsBody(
            viewModel: viewModel,
            compactList: true,
            scrollController: _eventScrollController,
          ))
        else
          _HomeEventsBody(
            viewModel: viewModel,
            compactList: false,
          ),
      ],
    );
  }
}

class _HomeEventsBody extends StatelessWidget {
  const _HomeEventsBody({
    required this.viewModel,
    required this.compactList,
    this.scrollController,
  });

  final AstronomyEventsViewModel viewModel;
  final bool compactList;
  final ScrollController? scrollController;

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
    final nowUtc = now.toUtc();
    final events = compactList
        ? (viewModel.events.where((event) {
            final instant = AstronomyEventPresenter.primaryInstant(event)?.toUtc();
            final end = event.endAt?.toUtc() ?? instant;
            return instant != null &&
                end != null &&
                !end.isBefore(nowUtc) &&
                instant.isBefore(DateTime.utc(2027, 6, 1));
          }).toList()..sort((a, b) {
            final aTime = AstronomyEventPresenter.primaryInstant(a)!.toUtc();
            final bTime = AstronomyEventPresenter.primaryInstant(b)!.toUtc();
            return aTime.compareTo(bTime);
          }))
        : viewModel.homeEvents;
    if (compactList) {
      if (events.isEmpty) {
        return const _SectionMessage(
          key: Key('astronomy-events-empty'),
          message: '표시 기간에 예정된 천문 이벤트가 없습니다.',
        );
      }
      return PcScrollBoundary(child: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: ListView.separated(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          itemCount: events.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: PcHomeColors.border),
          itemBuilder: (context, index) => InkWell(
              key: Key('astronomy-event-${events[index].id}'),
              onTap: () => AstronomyEventsScreen.open(
                context, showHomeNavigation: compactList,
              ),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: PcHomeColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PcHomeColors.border),
                      ),
                      child: Icon(
                        AstronomyEventPresenter.categoryIcon(events[index].type),
                        color: PcHomeColors.muted,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(events[index].title, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          Text(
                            events[index].tags.isEmpty
                                ? AstronomyEventPresenter.categoryLabel(events[index].type)
                                : events[index].tags.take(2).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10,
                                color: PcHomeColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSm),
                    SizedBox(
                      width: 92,
                      child: Text(
                        AstronomyEventPresenter.dateLabel(events[index], now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 10,
                            color: PcHomeColors.muted),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ));
    }
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
