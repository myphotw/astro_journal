import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../services/metadata_format.dart';

/// 적분시간을 분 단위 숫자로만 입력하고, 실시간으로 시/분 환산을 보여준다.
///
/// TextField 자체는 고정하고 helper만 갱신해 입력 중 버벅임을 줄인다.
class IntegrationMinutesField extends StatefulWidget {
  const IntegrationMinutesField({
    super.key,
    required this.controller,
    this.label = '총 적분시간',
    this.hintText = '30',
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  State<IntegrationMinutesField> createState() =>
      _IntegrationMinutesFieldState();
}

class _IntegrationMinutesFieldState extends State<IntegrationMinutesField> {
  static final _formatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
  ];

  String? _preview;

  @override
  void initState() {
    super.initState();
    _preview = MetadataFormat.formatMinutesLive(widget.controller.text);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant IntegrationMinutesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _preview = MetadataFormat.formatMinutesLive(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final next = MetadataFormat.formatMinutesLive(widget.controller.text);
    if (next == _preview || !mounted) return;
    setState(() => _preview = next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _formatters,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hintText,
              suffixText: '분',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _preview == null ? '숫자만 입력 (분 단위)' : '= $_preview',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
