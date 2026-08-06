import 'dart:convert';



import '../../core/constants/database_constants.dart';

import 'exif_info.dart';



/// 갤러리에서 선택해 앱 내부 저장소로 복사한 사진 모델.

class Photo {

  const Photo({

    required this.id,

    required this.localPath,

    required this.createdAt,

    this.originalFilename,

    this.exifInfo,

  });



  final String id;

  final String localPath;

  final String? originalFilename;

  final DateTime createdAt;

  final ExifInfo? exifInfo;



  Map<String, dynamic> toMap() {

    return {

      DatabaseConstants.colId: id,

      DatabaseConstants.colLocalPath: localPath,

      DatabaseConstants.colOriginalFilename: originalFilename,

      DatabaseConstants.colCreatedAt: createdAt.toIso8601String(),

      DatabaseConstants.colExifJson:

          exifInfo != null ? jsonEncode(exifInfo!.toJson()) : null,

    };

  }



  factory Photo.fromMap(Map<String, dynamic> map) {

    final exifJson = map[DatabaseConstants.colExifJson] as String?;

    return Photo(

      id: map[DatabaseConstants.colId] as String,

      localPath: map[DatabaseConstants.colLocalPath] as String,

      originalFilename: map[DatabaseConstants.colOriginalFilename] as String?,

      createdAt: DateTime.parse(

        map[DatabaseConstants.colCreatedAt] as String,

      ),

      exifInfo: exifJson != null && exifJson.isNotEmpty

          ? ExifInfo.fromJson(jsonDecode(exifJson) as Map<String, dynamic>)

          : null,

    );

  }

}


