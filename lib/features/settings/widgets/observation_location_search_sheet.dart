import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/geocoding_service.dart';

class ObservationLocationSearchSheet extends StatefulWidget {
  const ObservationLocationSearchSheet({
    super.key,
    required this.geocodingService,
    this.debounceDuration = const Duration(milliseconds: 350),
  });

  final GeocodingService geocodingService;
  final Duration debounceDuration;

  static Future<LocationSearchSuggestion?> show(
    BuildContext context, {
    required GeocodingService geocodingService,
  }) => showModalBottomSheet<LocationSearchSuggestion>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        ObservationLocationSearchSheet(geocodingService: geocodingService),
  );

  @override
  State<ObservationLocationSearchSheet> createState() =>
      _ObservationLocationSearchSheetState();
}

class _ObservationLocationSearchSheetState
    extends State<ObservationLocationSearchSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _requestGeneration = 0;
  bool _searching = false;
  String? _message;
  List<LocationSearchSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _requestGeneration++;
    _debounce?.cancel();
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() {
        _searching = false;
        _suggestions = const [];
        _message = query.isEmpty ? '주소나 장소 이름을 입력해 주세요.' : '두 글자 이상 입력해 주세요.';
      });
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
    });
    _debounce = Timer(
      widget.debounceDuration,
      () => unawaited(_search(query, generation)),
    );
  }

  Future<void> _search(String query, int generation) async {
    try {
      final suggestions = await widget.geocodingService.autocompleteLocations(
        query,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          query != _query.text.trim()) {
        return;
      }
      setState(() {
        _searching = false;
        _suggestions = suggestions;
        _message = suggestions.isEmpty ? '검색 결과가 없습니다.' : null;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _searching = false;
        _suggestions = const [];
        _message = '주소 검색에 실패했습니다. 기존 위치는 유지됩니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + keyboardInset),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('location-search-field'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: '주소 또는 장소 검색',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_searching)
              const LinearProgressIndicator(
                key: Key('location-search-progress'),
              ),
            Expanded(
              child: _suggestions.isEmpty
                  ? Center(
                      child: Text(
                        _message ?? '검색어를 입력해 주세요.',
                        key: const Key('location-search-message'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      key: const Key('location-search-results'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          key: Key('location-search-result-$index'),
                          leading: const Icon(Icons.place_outlined),
                          title: Text(suggestion.mainText),
                          subtitle: suggestion.secondaryText == null
                              ? null
                              : Text(suggestion.secondaryText!),
                          onTap: () => Navigator.pop(context, suggestion),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
