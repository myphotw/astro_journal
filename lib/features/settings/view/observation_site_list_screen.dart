import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/observation_site.dart';
import '../../../data/repositories/observation_site_repository.dart';
import '../../home/viewmodel/home_view_model.dart';
import '../../observation_site/view/observation_site_detail_screen.dart';
import '../../observation_site/viewmodel/active_observation_site_view_model.dart';
import 'observation_site_edit_screen.dart';

class ObservationSiteListScreen extends StatefulWidget {
  const ObservationSiteListScreen({super.key});

  @override
  State<ObservationSiteListScreen> createState() =>
      _ObservationSiteListScreenState();
}

class _ObservationSiteListScreenState extends State<ObservationSiteListScreen> {
  late Future<List<ObservationSite>> _sites;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _sites = context.read<ObservationSiteRepository>().list().then((sites) {
      sites.sort((a, b) {
        final recent = (b.lastUsedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.lastUsedAt?.millisecondsSinceEpoch ?? 0,
        );
        if (recent != 0) return recent;
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return sites;
    });
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _sites;
  }

  Future<void> _openEditor([ObservationSite? site]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ObservationSiteEditScreen(site: site)),
    );
    if (changed == true && mounted) await _refresh();
  }

  Future<void> _openDetail(ObservationSite site) async {
    HomeViewModel? home;
    ActiveObservationSiteViewModel? active;
    try {
      home = context.read<HomeViewModel>();
      active = context.read<ActiveObservationSiteViewModel>();
    } on ProviderNotFoundException {
      // The screen remains independently testable without the app-level shell.
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ObservationSiteDetailScreen(
          siteId: site.id,
          homeViewModel: home,
          activeViewModel: active,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _toggleFavorite(ObservationSite site) async {
    await context.read<ObservationSiteRepository>().setFavorite(
      site.id,
      !site.isFavorite,
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('관측지')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-observation-site'),
        onPressed: _openEditor,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('관측지 추가'),
      ),
      body: FutureBuilder<List<ObservationSite>>(
        future: _sites,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('관측지를 불러오지 못했습니다. 다시 시도'),
              ),
            );
          }
          final sites = snapshot.data ?? const [];
          if (sites.isEmpty) {
            return const Center(
              child: Text(
                '등록된 관측지가 없습니다.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: sites.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final site = sites[index];
                return Card(
                  color: AppColors.surface,
                  child: ListTile(
                    key: Key('observation-site-${site.id}'),
                    onTap: () => _openDetail(site),
                    leading: IconButton(
                      tooltip: site.isFavorite ? '즐겨찾기 해제' : '즐겨찾기',
                      onPressed: () => _toggleFavorite(site),
                      icon: Icon(
                        site.isFavorite ? Icons.star : Icons.star_border,
                        color: site.isFavorite
                            ? Colors.amber
                            : AppColors.textSecondary,
                      ),
                    ),
                    title: Text(site.name),
                    subtitle: Text(
                      [
                        if (site.address?.trim().isNotEmpty == true)
                          site.address!.trim(),
                        'Bortle ${site.bortle?.toString() ?? '-'}',
                        site.trackingMode.name == 'eq' ? 'EQ' : 'Alt-Az',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
