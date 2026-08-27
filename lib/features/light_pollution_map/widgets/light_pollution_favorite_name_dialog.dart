import 'package:flutter/material.dart';

class LightPollutionFavoriteNameDialog extends StatefulWidget {
  const LightPollutionFavoriteNameDialog({
    super.key,
    required this.defaultName,
  });

  final String defaultName;

  @override
  State<LightPollutionFavoriteNameDialog> createState() =>
      _LightPollutionFavoriteNameDialogState();
}

class _LightPollutionFavoriteNameDialogState
    extends State<LightPollutionFavoriteNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('즐겨찾기 이름'),
    content: TextField(
      key: const Key('light-map-favorite-name'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: '관측지 이름'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        key: const Key('light-map-save-favorite'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('저장'),
      ),
    ],
  );
}
