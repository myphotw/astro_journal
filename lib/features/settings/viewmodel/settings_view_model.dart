import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/database_constants.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../data/repositories/shooting_record_repository.dart';
import '../../../services/api_key_service.dart';
import '../../../services/backup_service.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(
    this._photoRepository,
    this._shootingRecordRepository,
    this._apiKeyService,
    this._backupService, {
    this.onDataChanged,
  });

  final PhotoRepository _photoRepository;
  final ShootingRecordRepository _shootingRecordRepository;
  final ApiKeyService _apiKeyService;
  final BackupService _backupService;

  /// 삭제 완료 후 다른 ViewModel의 데이터를 갱신하기 위한 콜백.
  final Future<void> Function()? onDataChanged;

  /// Exposed so that navigation code can pass it to child ViewModels.
  ApiKeyService get apiKeyService => _apiKeyService;

  Map<ApiKeyType, String?> _apiKeys = {};
  Map<ApiKeyType, String?> get apiKeys => Map.unmodifiable(_apiKeys);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 마지막 전체 삭제 결과 (사진 수 + 기록 수).
  int _lastDeletePhotoCount = 0;
  int _lastDeleteRecordCount = 0;
  int get lastDeletePhotoCount => _lastDeletePhotoCount;
  int get lastDeleteRecordCount => _lastDeleteRecordCount;

  Future<void> loadApiKeys() async {
    _apiKeys = await _apiKeyService.getAll();
    notifyListeners();
  }

  Future<void> saveApiKey(ApiKeyType type, String value) async {
    await _apiKeyService.save(type, value);
    _apiKeys = await _apiKeyService.getAll();
    notifyListeners();
  }

  Future<void> deleteApiKey(ApiKeyType type) async {
    await _apiKeyService.delete(type);
    _apiKeys = await _apiKeyService.getAll();
    notifyListeners();
  }

  /// 모든 사진 및 촬영기록을 한 번에 삭제하고 카탈로그 상태를 초기화한다.
  ///
  /// 처리 순서:
  ///   1. photos 테이블 전체 삭제 + 실제 파일 삭제
  ///   2. photos 디렉토리 내 고아 파일 정리
  ///   3. shooting_records 전체 삭제
  ///   4. celestial_objects captured 상태 초기화
  ///   5. onDataChanged 콜백 호출 → 다른 ViewModel 즉시 갱신
  ///
  /// 삭제된 사진 수와 기록 수를 ({photos, records}) 로 반환한다.
  Future<({int photos, int records})> deleteAll() async {
    _setLoading(true);
    try {
      // ── 사진 삭제 ────────────────────────────────────────────
      final photos = await _photoRepository.getAll();
      for (final photo in photos) {
        final file = File(photo.localPath);
        if (file.existsSync()) file.deleteSync();
        await _photoRepository.delete(photo.id);
      }

      // photos 디렉토리 내 고아 파일 정리
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(p.join(appDir.path, 'photos'));
      if (photosDir.existsSync()) {
        for (final entity in photosDir.listSync()) {
          if (entity is File) entity.deleteSync();
        }
      }

      // ── 촬영기록 삭제 ────────────────────────────────────────
      final records = await _shootingRecordRepository.getAll();
      for (final record in records) {
        await _shootingRecordRepository.delete(record.id);
      }

      // ── 카탈로그 captured 상태 초기화 ───────────────────────
      final db = await AppDatabase.instance;
      await db.update(
        DatabaseConstants.tableCelestialObjects,
        {
          DatabaseConstants.colCaptured: 0,
          DatabaseConstants.colCapturedDate: null,
        },
      );

      _lastDeletePhotoCount = photos.length;
      _lastDeleteRecordCount = records.length;
      notifyListeners();

      // ── 다른 ViewModel 즉시 갱신 ────────────────────────────
      await onDataChanged?.call();

      return (photos: photos.length, records: records.length);
    } finally {
      _setLoading(false);
    }
  }

  Future<String> exportBackup({BackupProgressCallback? onProgress}) async {
    // isLoading을 켜지 않는다 — SettingsScreen이 ListView를 스피너로
    // 교체하면 백업 UI context가 dispose되어 저장 화면이 안 뜬다.
    try {
      return await _backupService.exportBackup(onProgress: onProgress);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 폴더 선택 후 ZIP 저장. 취소 시 null.
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
    // export와 동일 — 전역 isLoading으로 설정 본문을 바꾸지 않는다.
    try {
      await _backupService.importBackup(zipPath, onProgress: onProgress);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 가져올 백업 ZIP 선택. 취소 시 null.
  Future<String?> pickBackupZipForImport() {
    return _backupService.pickBackupZipForImport();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
