import 'package:flutter/foundation.dart';

import '../data/models/exif_info.dart';

import '../data/models/photo_metadata.dart';

import '../data/models/seestar_metadata.dart';

import 'app_logger.dart';

import 'exif_copy_diagnostic.dart';

import 'exif_service.dart';

import 'metadata_field_trace.dart';

import 'metadata_service.dart';

import 'seestar_filename_parser.dart';

import 'seestar_metadata_pipeline.dart';



/// EXIF 추출 → Seestar 파싱 → 병합 → ExifInfo 반영까지의 단일 파이프라인.

class PhotoMetadataPipeline {

  PhotoMetadataPipeline({

    SeestarMetadataPipeline? seestarPipeline,

    MetadataService? metadataService,

    SeestarFilenameParser? filenameParser,

    ExifService? exifService,

  })  : _seestarPipeline = seestarPipeline ?? const SeestarMetadataPipeline(),

        _metadataService = metadataService ?? const MetadataService(),

        _filenameParser = filenameParser ?? const SeestarFilenameParser(),

        _exifService = exifService ?? ExifService();



  final SeestarMetadataPipeline _seestarPipeline;

  final MetadataService _metadataService;

  final SeestarFilenameParser _filenameParser;

  final ExifService _exifService;



  /// [exif]와 [originalFilename]으로부터 병합된 메타데이터와 enriched ExifInfo를 생성한다.

  Future<PhotoMetadataProcessResult> process({

    required ExifInfo exif,

    required String originalFilename,

    String? imagePath,

    StringBuffer? parseAnalysisLog,

  }) async {

    AppLogger.metadata('Pipeline', 'Exif 추출 완료');



    var exifInput = exif.copyWith(

      filename: originalFilename,

      originalFilename: originalFilename,

    );



    if (imagePath != null) {

      exifInput = await _exifService.enrichSeestarRawTags(exifInput, imagePath);

    }



    if (kDebugMode) {
      ExifCopyDiagnostic.logPipelineJson(
        makerNoteJson: exifInput.makerNoteJson,
        ownerNameJson: exifInput.ownerNameJson,
      );
    }

    MetadataFieldTrace.logMakerNoteRaw(exifInput.makerNoteJson);

    MetadataFieldTrace.logExifInfo('Pipeline.Input', exifInput);

    MetadataFieldTrace.logSeestarMerge('Before Merge', exifInput);



    SeestarMetadata? makerNoteMetadata;

    final makerNoteRaw = exifInput.makerNoteJson;

    if (makerNoteRaw != null && makerNoteRaw.trim().isNotEmpty) {

      AppLogger.metadata('Pipeline', 'MakerNote 발견');

      makerNoteMetadata = _seestarPipeline.parseMakerNote(
        makerNoteRaw,
        analysisLog: parseAnalysisLog,
      );

      MetadataFieldTrace.logParser('MakerNote', makerNoteMetadata);

      if (makerNoteMetadata != null) {

        AppLogger.metadata('Pipeline', 'MakerNote Parser 성공');

      } else {

        AppLogger.metadata('Pipeline', 'MakerNote Parser 실패');

      }

    } else {

      AppLogger.metadata('Pipeline', 'MakerNote 없음');

    }



    SeestarMetadata? ownerNameMetadata;

    final ownerRaw = exifInput.ownerNameJson;

    if (ownerRaw != null && ownerRaw.trim().isNotEmpty) {

      AppLogger.metadata('Pipeline', 'CameraOwnerName 발견');

      ownerNameMetadata = _seestarPipeline.parseCameraOwnerName(
        ownerRaw,
        analysisLog: parseAnalysisLog,
      );

      MetadataFieldTrace.logParser('CameraOwnerName', ownerNameMetadata);

      if (ownerNameMetadata != null) {

        AppLogger.metadata('Pipeline', 'CameraOwnerName Parser 성공');

      } else {

        AppLogger.metadata('Pipeline', 'CameraOwnerName Parser 실패');

      }

    } else {

      AppLogger.metadata('Pipeline', 'CameraOwnerName 없음');

    }



    final hasSeestarMetadata =

        makerNoteMetadata != null || ownerNameMetadata != null;



    SeestarMetadata? filenameMetadata;

    if (hasSeestarMetadata) {

      AppLogger.metadata(

        'Pipeline',

        'FileName Skip (Seestar metadata exists)',

      );

    } else {

      filenameMetadata = _filenameParser.parse(originalFilename);

      MetadataFieldTrace.logParser('FileName', filenameMetadata);

      if (filenameMetadata != null) {

        AppLogger.metadata(

          'Pipeline',

          'FileName Parse Success — 대상=${filenameMetadata.objName ?? "없음"}',

        );

      } else {

        AppLogger.metadata(

          'Pipeline',

          'FileName Parse Fail ($originalFilename)',

        );

      }

    }



    exifInput = _metadataService.mergeSeestarIntoExifInfo(
      exifInput,
      makerNote: makerNoteMetadata,
      ownerName: ownerNameMetadata,
      filename: filenameMetadata,
    );

    MetadataFieldTrace.logSeestarMerge('After Merge', exifInput);

    if (MetadataFieldTrace.hasMissingSeestarFields(exifInput) &&
        (makerNoteMetadata != null ||
            ownerNameMetadata != null ||
            filenameMetadata != null)) {
      MetadataFieldTrace.logParserDump(
        makerNote: makerNoteMetadata,
        ownerName: ownerNameMetadata,
        filename: filenameMetadata,
      );
    }



    PhotoMetadata metadata;

    try {

      metadata = _metadataService.merge(

        exif: exifInput,

        makerNote: makerNoteMetadata,

        ownerName: ownerNameMetadata,

        filename: filenameMetadata,

      );

      MetadataFieldTrace.logPhotoMetadata('Merge', metadata);

      AppLogger.metadata('Pipeline', 'Metadata 병합 완료');

    } catch (e, stack) {

      AppLogger.metadata('Pipeline', 'Metadata Merge 실패: $e');

      AppLogger.error('PhotoMetadataPipeline.merge', e, stack);

      rethrow;

    }



    final enrichedExif = _metadataService.buildEnrichedExifInfo(

      exifInput,

      metadata,

    );

    MetadataFieldTrace.logExifInfo('Enriched', enrichedExif);



    return PhotoMetadataProcessResult(

      exifInfo: enrichedExif,

      metadata: metadata,

      makerNoteMetadata: makerNoteMetadata,

      ownerNameMetadata: ownerNameMetadata,

      filenameMetadata: filenameMetadata,

    );

  }

  /// EXIF 디버그 화면용 인스턴스 생성.
  static PhotoMetadataPipeline forDebug(ExifService exifService) {
    return forDebugImpl(exifService);
  }
}



PhotoMetadataPipeline forDebugImpl(ExifService exifService) {
  return PhotoMetadataPipeline(
    exifService: exifService,
  );
}

class PhotoMetadataProcessResult {

  const PhotoMetadataProcessResult({

    required this.exifInfo,

    required this.metadata,

    this.makerNoteMetadata,

    this.ownerNameMetadata,

    this.filenameMetadata,

  });



  final ExifInfo exifInfo;

  final PhotoMetadata metadata;

  final SeestarMetadata? makerNoteMetadata;

  final SeestarMetadata? ownerNameMetadata;

  final SeestarMetadata? filenameMetadata;

}

