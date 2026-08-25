class AstroJournalResetPreview {
  const AstroJournalResetPreview({
    required this.observationRecordCount,
    required this.astroFileCount,
    required this.astroOnlyFileCount,
    required this.sharedFileCount,
    required this.plateSolveResultCount,
    required this.photoObjectCount,
    required this.uploadJobCount,
    required this.pendingUploadCount,
    required this.processingUploadCount,
    required this.processingVisionJobCount,
    required this.processingJobCount,
    required this.physicalOriginalDeleteCount,
    required this.physicalPreviewDeleteCount,
    required this.physicalThumbnailDeleteCount,
    required this.preservedSharedFileCount,
    required this.resetBlocked,
    this.blockedReason,
  });

  final int observationRecordCount;
  final int astroFileCount;
  final int astroOnlyFileCount;
  final int sharedFileCount;
  final int plateSolveResultCount;
  final int photoObjectCount;
  final int uploadJobCount;
  final int pendingUploadCount;
  final int processingUploadCount;
  final int processingVisionJobCount;
  final int processingJobCount;
  final int physicalOriginalDeleteCount;
  final int physicalPreviewDeleteCount;
  final int physicalThumbnailDeleteCount;
  final int preservedSharedFileCount;
  final bool resetBlocked;
  final String? blockedReason;

  factory AstroJournalResetPreview.fromJson(Map<String, dynamic> json) {
    return AstroJournalResetPreview(
      observationRecordCount: _requiredInt(json, 'observation_record_count'),
      astroFileCount: _requiredInt(json, 'astro_file_count'),
      astroOnlyFileCount: _requiredInt(json, 'astro_only_file_count'),
      sharedFileCount: _requiredInt(json, 'shared_file_count'),
      plateSolveResultCount: _requiredInt(json, 'plate_solve_result_count'),
      photoObjectCount: _requiredInt(json, 'photo_object_count'),
      uploadJobCount: _requiredInt(json, 'upload_job_count'),
      pendingUploadCount: _requiredInt(json, 'pending_upload_count'),
      processingUploadCount: _requiredInt(json, 'processing_upload_count'),
      processingVisionJobCount: _requiredInt(
        json,
        'processing_vision_job_count',
      ),
      processingJobCount: _requiredInt(json, 'processing_job_count'),
      physicalOriginalDeleteCount: _requiredInt(
        json,
        'physical_original_delete_count',
      ),
      physicalPreviewDeleteCount: _requiredInt(
        json,
        'physical_preview_delete_count',
      ),
      physicalThumbnailDeleteCount: _requiredInt(
        json,
        'physical_thumbnail_delete_count',
      ),
      preservedSharedFileCount: _requiredInt(
        json,
        'preserved_shared_file_count',
      ),
      resetBlocked: _requiredBool(json, 'reset_blocked'),
      blockedReason: _optionalString(json['blocked_reason']),
    );
  }
}

class AstroJournalResetResult {
  const AstroJournalResetResult({
    required this.resetCompleted,
    required this.deletedObservationRecordCount,
    required this.removedAstroFileLinkCount,
    required this.tombstonedCommonFileCount,
    required this.preservedSharedFileCount,
    required this.deletedUploadJobCount,
    required this.deletedOriginalCount,
    required this.deletedPreviewCount,
    required this.deletedThumbnailCount,
    required this.deletedPlateSolveResultCount,
    required this.deletedPhotoObjectCount,
    required this.resetEventCursor,
  });

  final bool resetCompleted;
  final int deletedObservationRecordCount;
  final int removedAstroFileLinkCount;
  final int tombstonedCommonFileCount;
  final int preservedSharedFileCount;
  final int deletedUploadJobCount;
  final int deletedOriginalCount;
  final int deletedPreviewCount;
  final int deletedThumbnailCount;
  final int deletedPlateSolveResultCount;
  final int deletedPhotoObjectCount;
  final int resetEventCursor;

  factory AstroJournalResetResult.fromJson(Map<String, dynamic> json) {
    return AstroJournalResetResult(
      resetCompleted: _requiredBool(json, 'reset_completed'),
      deletedObservationRecordCount: _requiredInt(
        json,
        'deleted_observation_record_count',
      ),
      removedAstroFileLinkCount: _requiredInt(
        json,
        'removed_astro_file_link_count',
      ),
      tombstonedCommonFileCount: _requiredInt(
        json,
        'tombstoned_common_file_count',
      ),
      preservedSharedFileCount: _requiredInt(
        json,
        'preserved_shared_file_count',
      ),
      deletedUploadJobCount: _requiredInt(json, 'deleted_upload_job_count'),
      deletedOriginalCount: _requiredInt(json, 'deleted_original_count'),
      deletedPreviewCount: _requiredInt(json, 'deleted_preview_count'),
      deletedThumbnailCount: _requiredInt(json, 'deleted_thumbnail_count'),
      deletedPlateSolveResultCount: _requiredInt(
        json,
        'deleted_plate_solve_result_count',
      ),
      deletedPhotoObjectCount: _requiredInt(json, 'deleted_photo_object_count'),
      resetEventCursor: _requiredInt(json, 'reset_event_cursor'),
    );
  }
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Missing or invalid $key.');
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Missing or invalid $key.');
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
