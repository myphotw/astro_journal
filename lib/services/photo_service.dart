import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/models/exif_info.dart';
import '../data/models/photo.dart';
import '../data/repositories/photo_repository.dart';
import 'app_logger.dart';
import 'exif_copy_diagnostic.dart';
import 'exif_service.dart';

/// 갤러리에서 사진을 선택해 앱 내부 저장소로 복사한 결과.
class PhotoPickResult {
  const PhotoPickResult({
    required this.id,
    required this.localPath,
    required this.originalFilename,
    required this.exifInfo,
  });

  final String id;
  final String localPath;

  /// 갤러리 원본 파일명 (UUID 복사 전).
  final String originalFilename;
  final ExifInfo exifInfo;
}

/// 갤러리 사진 선택 → 앱 내부 저장소 복사 → EXIF 추출 → DB 저장.
class PhotoService {
  PhotoService(this._photoRepository, this._exifService);

  final PhotoRepository _photoRepository;
  final ExifService _exifService;
  final _picker = ImagePicker();
  static const _uuid = Uuid();

  /// 갤러리에서 사진을 선택하고 앱 내부 저장소로 복사한 뒤
  /// EXIF를 추출하여 DB에 저장한다.
  /// 사용자가 선택을 취소하면 null을 반환한다.
  Future<Photo?> pickAndSave() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    final id = _uuid.v4();
    final ext = p.extension(picked.path).toLowerCase();
    final localPath = p.join(photosDir.path, '$id$ext');
    final originalFilename = p.basename(picked.path);

    await File(picked.path).copy(localPath);

    final exifInfo = await _exifService.extractFromPath(
      localPath,
      originalFilename: originalFilename,
    );

    final photo = Photo(
      id: id,
      localPath: localPath,
      originalFilename: originalFilename,
      createdAt: DateTime.now(),
      exifInfo: exifInfo,
    );

    await _photoRepository.save(photo);
    return photo;
  }

  /// 갤러리에서 여러 장을 선택하고 각각 복사 + EXIF 추출한다.
  /// 사용자가 선택을 취소하면 빈 리스트를 반환한다.
  Future<List<PhotoPickResult>> pickMultipleAndCopyOnly() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return [];

    return copyPickedFiles(
      picked.map((file) => File(file.path)).toList(growable: false),
    );
  }

  /// 앱 갤러리 화면 등에서 받은 파일 목록을 복사 + EXIF 추출한다.
  Future<List<PhotoPickResult>> copyPickedFiles(List<File> files) async {
    final results = <PhotoPickResult>[];
    for (final file in files) {
      final result = await _copyPickedFile(XFile(file.path), extractExif: true);
      if (result != null) results.add(result);
    }
    return results;
  }

  /// 파일만 복사하고 EXIF는 placeholder로 둔다 (UI 선표시용).
  Future<List<PhotoPickResult>> copyPickedFilesWithoutExif(
    List<File> files,
  ) async {
    final results = <PhotoPickResult>[];
    for (final file in files) {
      final result = await _copyPickedFile(XFile(file.path), extractExif: false);
      if (result != null) results.add(result);
      await Future<void>.delayed(Duration.zero);
    }
    return results;
  }

  /// 플랫폼별 파일 선택 UI와 분리된 경로 기반 복사 진입점.
  ///
  /// Windows 등록 화면처럼 시스템 파일 선택기가 반환한 경로도 모바일과
  /// 동일하게 앱 관리 저장소로 복사하고, 이후 메타데이터 파이프라인을
  /// 지연 실행할 수 있게 한다.
  Future<List<PhotoPickResult>> copyFilePathsWithoutExif(
    List<String> paths,
  ) {
    return copyPickedFilesWithoutExif(
      paths.map(File.new).toList(growable: false),
    );
  }

  Future<PhotoPickResult?> _copyPickedFile(
    XFile picked, {
    bool extractExif = true,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    final id = _uuid.v4();
    final ext = p.extension(picked.path).toLowerCase();
    final localPath = p.join(photosDir.path, '$id$ext');
    final originalFilename = p.basename(picked.path);

    if (kDebugMode) {
      AppLogger.metadata(
        'ExifCopyDiag',
        '[ImagePicker] picked.path = ${picked.path}',
      );

      final beforeTags = await ExifCopyDiagnostic.dumpFile(
        picked.path,
        'BEFORE_COPY (picked.path)',
      );

      try {
        await File(picked.path).copy(localPath);
      } on FileSystemException catch (error, stack) {
        AppLogger.error('PhotoService', error, stack);
        return null;
      }

      AppLogger.metadata('ExifCopyDiag', '[File.copy] UUID path = $localPath');

      final afterTags = await ExifCopyDiagnostic.dumpFile(
        localPath,
        'AFTER_COPY (UUID)',
      );
      ExifCopyDiagnostic.compare(beforeTags, afterTags);
    } else {
      try {
        await File(picked.path).copy(localPath);
      } on FileSystemException catch (error, stack) {
        AppLogger.error('PhotoService', error, stack);
        return null;
      }
    }

    final exifInfo = extractExif
        ? await _exifService.extractFromPath(
            localPath,
            originalFilename: originalFilename,
          )
        : ExifInfo.placeholder(filename: originalFilename);

    return PhotoPickResult(
      id: id,
      localPath: localPath,
      originalFilename: originalFilename,
      exifInfo: exifInfo,
    );
  }

  /// 갤러리에서 사진을 선택하고 앱 내부 저장소로 복사한 뒤 EXIF를 추출한다.
  ///
  /// DB에는 저장하지 않는다. 메타데이터 확인 후 [savePickResult]로 저장한다.
  /// 사용자가 선택을 취소하면 null을 반환한다.
  Future<PhotoPickResult?> pickAndCopyOnly({bool extractExif = true}) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return _copyPickedFile(picked, extractExif: extractExif);
  }

  /// [pickAndCopyOnly]로 복사한 사진을 Photo DB에 저장한다.
  Future<void> savePickResult(PhotoPickResult result) async {
    final photo = Photo(
      id: result.id,
      localPath: result.localPath,
      originalFilename: result.originalFilename,
      createdAt: DateTime.now(),
      exifInfo: result.exifInfo,
    );
    await _photoRepository.save(photo);
  }

  /// DB 레코드와 내부 저장소 파일을 모두 삭제한다.
  Future<void> deletePhoto(Photo photo) async {
    final file = File(photo.localPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    await _photoRepository.delete(photo.id);
  }
}
