import 'package:flutter/material.dart';

import '../../../data/models/astrojournal_reset.dart';
import '../../../services/astrojournal_capture_reset_coordinator.dart';
import '../../../services/backup_service.dart';
import '../../../services/tc_backend_astrojournal_reset_service.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._captureReset, this._backupService);

  final AstroJournalCaptureResetCoordinator _captureReset;
  final BackupService _backupService;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AstroJournalResetPreview? _resetPreview;
  AstroJournalResetPreview? get resetPreview => _resetPreview;

  AstroJournalResetResult? _lastResetResult;
  AstroJournalResetResult? get lastResetResult => _lastResetResult;

  Future<AstroJournalResetPreview> previewCaptureReset() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final preview = await _captureReset.preview();
      _resetPreview = preview;
      return preview;
    } catch (error) {
      _errorMessage = resetUserMessage(error);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<AstroJournalResetResult> executeCaptureReset() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final result = await _captureReset.execute();
      _lastResetResult = result;
      _resetPreview = null;
      return result;
    } catch (error) {
      _errorMessage = resetUserMessage(error);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  static String resetUserMessage(Object error) {
    if (error is AstroJournalResetException) return error.userMessage;
    return '촬영 데이터 초기화를 완료하지 못했습니다. 잠시 후 다시 시도해주세요.';
  }

  Future<String> exportBackup({BackupProgressCallback? onProgress}) async {
    try {
      return await _backupService.exportBackup(onProgress: onProgress);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<BackupSaveResult?> saveBackupToChosenFolder(String zipPath) {
    return _backupService.saveBackupToChosenFolder(zipPath);
  }

  Future<BackupSaveResult?> saveBackupWithSaveDialog(String zipPath) {
    return _backupService.saveBackupWithSaveDialog(zipPath);
  }

  Future<void> shareBackupFile(String zipPath) {
    return _backupService.shareBackupFile(zipPath);
  }

  Future<void> openSavedBackup(BackupSaveResult result) {
    return _backupService.openSavedBackup(result);
  }

  Future<void> importBackup(
    String zipPath, {
    BackupProgressCallback? onProgress,
  }) async {
    try {
      await _backupService.importBackup(zipPath, onProgress: onProgress);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> pickBackupZipForImport() {
    return _backupService.pickBackupZipForImport();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
