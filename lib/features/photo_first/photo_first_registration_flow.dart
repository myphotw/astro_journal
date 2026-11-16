import 'package:flutter/material.dart';

import '../../data/models/shooting_record.dart';
import '../desktop/view/pc_photo_registration_screen.dart';

/// Main entry opens the same registration workspace as the desktop tab.
/// File selection and durable saving both happen inside that workspace.
Future<void> runPhotoFirstRegistrationFlow(BuildContext context) async {
  final savedRecords = await Navigator.of(context).push<List<ShootingRecord>>(
    MaterialPageRoute(
      builder: (_) => const PcPhotoRegistrationScreen(popWhenFinished: true),
    ),
  );
  if (!context.mounted || savedRecords == null || savedRecords.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('사진 ${savedRecords.length}장이 저장되었습니다.')),
  );
}
