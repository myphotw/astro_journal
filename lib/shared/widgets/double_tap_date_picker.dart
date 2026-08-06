import 'package:flutter/material.dart';

/// 달력에서 같은 날짜를 빠르게 두 번 탭하면 확인과 동일하게 선택한다.
Future<DateTime?> showDoubleTapDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (dialogContext) {
      var selected = initialDate;
      DateTime? lastTapDay;
      var lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
            content: SizedBox(
              width: 340,
              height: 360,
              child: CalendarDatePicker(
                initialDate: selected,
                firstDate: firstDate,
                lastDate: lastDate,
                onDateChanged: (date) {
                  final now = DateTime.now();
                  final sameDay = lastTapDay != null &&
                      lastTapDay!.year == date.year &&
                      lastTapDay!.month == date.month &&
                      lastTapDay!.day == date.day;
                  if (sameDay &&
                      now.difference(lastTapAt) <
                          const Duration(milliseconds: 450)) {
                    Navigator.pop(dialogContext, date);
                    return;
                  }
                  lastTapDay = date;
                  lastTapAt = now;
                  setState(() => selected = date);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    },
  );
}
