import 'package:flutter/material.dart';

import '../../services/metadata_format.dart';

/// Material DatePicker + TimePicker로 일시를 선택하는 입력 필드.
class MaterialDateTimePickerField extends StatelessWidget {
  const MaterialDateTimePickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '촬영일시',
    this.hintText = '날짜와 시간을 선택하세요',
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String label;
  final String hintText;

  static Future<DateTime?> pick(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final now = DateTime.now();
    final initialDate = initial ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null || !context.mounted) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      initial?.second ?? 0,
    );
  }

  static DateTime? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
  }

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : MetadataFormat.formatDateTimeInput(value!.toIso8601String());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final picked = await pick(context, initial: value ?? DateTime.now());
          if (picked != null) onChanged(picked);
        },
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: const Icon(Icons.calendar_month_outlined),
          ),
          child: Text(
            text.isEmpty ? hintText : text,
            style: TextStyle(
              color: text.isEmpty
                  ? Theme.of(context).hintColor
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}
