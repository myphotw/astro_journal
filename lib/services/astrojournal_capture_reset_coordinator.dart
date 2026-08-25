import '../data/models/astrojournal_reset.dart';
import 'astrojournal_local_capture_reset_service.dart';
import 'tc_backend_astrojournal_reset_service.dart';
import 'tc_backend_sync_gate.dart';

class AstroJournalCaptureResetCoordinator {
  const AstroJournalCaptureResetCoordinator(
    this._api,
    this._localReset,
    this._syncGate,
  );

  final AstroJournalResetApi _api;
  final AstroJournalLocalCaptureReset _localReset;
  final TcBackendSyncGate _syncGate;

  Future<AstroJournalResetPreview> preview() => _api.preview();

  Future<AstroJournalResetResult> execute() {
    return _syncGate.runExclusive(() async {
      final result = await _api.execute();
      await _localReset.clearCaptureData(
        resetEventCursor: result.resetEventCursor.toString(),
      );
      return result;
    });
  }
}
