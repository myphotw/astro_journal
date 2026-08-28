import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/astronomy_event.dart';
import '../presentation/astronomy_event_presenter.dart';
import '../viewmodel/astronomy_events_view_model.dart';
import 'widgets/astronomy_event_card.dart';

class AstronomyEventsScreen extends StatefulWidget {
  const AstronomyEventsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AstronomyEventsScreen()),
  );

  @override
  State<AstronomyEventsScreen> createState() => _AstronomyEventsScreenState();
}

class _AstronomyEventsScreenState extends State<AstronomyEventsScreen> {
  bool _requestedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedLoad) return;
    _requestedLoad = true;
    final viewModel = context.read<AstronomyEventsViewModel>();
    if (!viewModel.hasLoaded) scheduleMicrotask(() => viewModel.load());
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AstronomyEventsViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('천문 이벤트')),
      body: _AllEventsBody(viewModel: viewModel),
    );
  }
}

class _AllEventsBody extends StatelessWidget {
  const _AllEventsBody({required this.viewModel});

  final AstronomyEventsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading && viewModel.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null && viewModel.events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                viewModel.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppTheme.spacingSm),
              FilledButton.tonal(
                key: const Key('retry-all-astronomy-events'),
                onPressed: viewModel.refresh,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    if (viewModel.events.isEmpty) {
      return const Center(
        child: Text(
          '예정된 주요 천문 이벤트가 없습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final groups = <String, List<AstronomyEvent>>{};
    for (final event in viewModel.events) {
      groups
          .putIfAbsent(
            AstronomyEventPresenter.monthGroupLabel(event),
            () => <AstronomyEvent>[],
          )
          .add(event);
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppTheme.spacingSm,
                bottom: AppTheme.spacingSm,
              ),
              child: Text(
                entry.key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final event in entry.value) ...[
              AstronomyEventCard(event: event, now: now),
              const SizedBox(height: AppTheme.spacingSm),
            ],
          ],
        ],
      ),
    );
  }
}
