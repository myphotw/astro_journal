import 'package:flutter/material.dart';

/// Registration uses a calendar date; an existing EXIF time is left untouched
/// until the user explicitly chooses another date.
class MaterialCaptureDateField extends StatelessWidget {
  const MaterialCaptureDateField({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final date = value;
    final label = date == null
        ? '촬영일을 선택하세요'
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final selected = await showDatePicker(
            context: context,
            locale: const Locale('ko', 'KR'),
            initialDate: date ?? now,
            firstDate: DateTime(1990),
            lastDate: DateTime(now.year + 1),
          );
          if (selected != null && context.mounted) {
            onChanged(DateTime(selected.year, selected.month, selected.day));
          }
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: '촬영일',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.calendar_month_outlined),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
