import 'dart:convert';

import 'dart:io';



import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:path/path.dart' as p;

import 'package:provider/provider.dart';



import '../../../core/theme/app_colors.dart';

import '../../../data/models/exif_info.dart';
import '../../../data/models/photo_metadata.dart';

import '../../../services/exif_service.dart';

import '../../../services/metadata_field_trace.dart';
import '../../../services/metadata_format.dart';
import '../../../services/photo_metadata_pipeline.dart';
import '../../../services/photo_service.dart';



/// 메타데이터 파싱 과정을 4개 탭으로 시각화하는 개발자 디버그 화면.

class MetadataDebugScreen extends StatefulWidget {

  const MetadataDebugScreen({super.key});



  @override

  State<MetadataDebugScreen> createState() => _MetadataDebugScreenState();

}



class _MetadataDebugScreenState extends State<MetadataDebugScreen>

    with SingleTickerProviderStateMixin {

  static final _metadataPipeline = PhotoMetadataPipeline();



  late final TabController _tabController;



  bool _isPicking = false;

  String? _photoPath;

  Map<String, String> _exifRaw = {};

  String? _makerNoteRaw;

  String? _ownerNameRaw;

  Map<String, String> _filenameResult = {};

  PhotoMetadata? _mergedMetadata;

  ExifInfo? _displayExif;

  String? _errorMessage;



  @override

  void initState() {

    super.initState();

    _tabController = TabController(length: 4, vsync: this);

  }



  @override

  void dispose() {

    _tabController.dispose();

    super.dispose();

  }



  Future<void> _pickAndAnalyze() async {

    setState(() {

      _isPicking = true;

      _errorMessage = null;

    });



    try {

      final photoService = context.read<PhotoService>();

      final picked = await photoService.pickAndCopyOnly();

      if (!mounted) return;

      if (picked == null) {

        setState(() => _isPicking = false);

        return;

      }



      _photoPath = picked.localPath;



      final allAttrs = await context.read<ExifService>().dumpAllAttributes(picked.localPath);
      final processed = await _metadataPipeline.process(
        exif: picked.exifInfo,
        originalFilename: picked.originalFilename,
        imagePath: picked.localPath,
      );
      final exifInfo = processed.exifInfo;
      MetadataFieldTrace.logUiValues('MetadataDebug', exifInfo);



      final exifRaw = <String, String>{

        if (exifInfo.equipment.isNotEmpty) '장비명 (Make+Model)': exifInfo.equipment,

        if (exifInfo.date.isNotEmpty) 'DateTimeOriginal': exifInfo.date,

        if (exifInfo.lat != null) 'GPSLatitude': exifInfo.lat!.toStringAsFixed(8),

        if (exifInfo.lng != null) 'GPSLongitude': exifInfo.lng!.toStringAsFixed(8),

        if (exifInfo.exposure.isNotEmpty) 'ExposureTime': exifInfo.exposure,

        if (exifInfo.fstop.isNotEmpty) 'FNumber': exifInfo.fstop,

        if (exifInfo.iso.isNotEmpty) 'ISOSpeedRatings': exifInfo.iso,

        if (exifInfo.focal.isNotEmpty) 'FocalLength': exifInfo.focal,

        if (exifInfo.imageWidth != null) 'PixelXDimension': '${exifInfo.imageWidth}',

        if (exifInfo.imageHeight != null) 'PixelYDimension': '${exifInfo.imageHeight}',

        if (exifInfo.resolution.isNotEmpty) '해상도': exifInfo.resolution,

        if (exifInfo.size.isNotEmpty) '파일크기': exifInfo.size,

        ...allAttrs,

      };



      _makerNoteRaw = exifInfo.makerNoteJson ?? allAttrs['MakerNote'];

      _ownerNameRaw =
          exifInfo.ownerNameJson ?? allAttrs['CameraOwnerName'] ?? allAttrs['OwnerName'];

      final filenameMeta = processed.filenameMetadata;

      final filenameResult = <String, String>{

        '원본 파일명': picked.originalFilename,

        '저장 파일명': p.basename(picked.localPath),

        if (processed.makerNoteMetadata != null ||
            processed.ownerNameMetadata != null)
          '결과': 'Seestar 메타 존재 — 파일명 분석 생략',

        if (filenameMeta?.objName != null) '대상명': filenameMeta!.objName!,

        if (filenameMeta?.stackNum != null) '스택 수': '${filenameMeta!.stackNum}',

        if (filenameMeta?.expSec != null) '1장 노출': '${filenameMeta!.expSec}s',

        if (filenameMeta?.filter != null) '필터': filenameMeta!.filter!,

        if (filenameMeta?.date != null) '날짜': filenameMeta!.date!,

        if (filenameMeta == null &&
            processed.makerNoteMetadata == null &&
            processed.ownerNameMetadata == null)
          '결과': '패턴 불일치 (비표준 파일명)',

      };

      final merged = processed.metadata;



      if (!mounted) return;

      setState(() {

        _exifRaw = exifRaw;

        _filenameResult = filenameResult;

        _mergedMetadata = merged;

        _displayExif = exifInfo;

        _isPicking = false;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() {

        _errorMessage = e.toString();

        _isPicking = false;

      });

    }

  }



  Future<void> _copyToClipboard(String text) async {

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      const SnackBar(content: Text('클립보드에 복사되었습니다.')),

    );

  }



  String _prettyJson(String? raw) {

    if (raw == null || raw.trim().isEmpty) return '(없음)';

    try {

      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));

    } catch (_) {

      return raw;

    }

  }



  String _mergedText() {

    final exif = _displayExif;

    if (exif == null) return '(없음)';

    final dateText = exif.date.isNotEmpty
        ? MetadataFormat.formatDateTimeInput(exif.date)
        : '-';
    final gpsText = exif.lat != null && exif.lng != null
        ? '${exif.lat!.toStringAsFixed(6)}, ${exif.lng!.toStringAsFixed(6)}'
        : '-';

    final lines = <String>[
      'Target: ${exif.targetName ?? "-"} (ExifInfo.targetName)',
      'Date: $dateText (ExifInfo.date)',
      'Equipment: ${exif.equipment.isNotEmpty ? exif.equipment : "-"} (ExifInfo.equipment)',
      'GPS: $gpsText (ExifInfo.lat/lng)',
      'StackNum: ${exif.stackNum ?? "-"} (ExifInfo.stackNum)',
      'ExpSec: ${exif.singleExpSec ?? "-"} (ExifInfo.singleExpSec)',
      'TotExpSec: ${exif.exposure.isNotEmpty ? exif.exposure : "-"} (ExifInfo.exposure)',
      'ISO: ${exif.iso.isNotEmpty ? exif.iso : "-"} (ExifInfo.iso)',
      'FStop: ${exif.fstop.isNotEmpty ? exif.fstop : "-"} (ExifInfo.fstop)',
      'Focal: ${exif.focal.isNotEmpty ? exif.focal : "-"} (ExifInfo.focal)',
    ];

    return lines.join('\n');

  }



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text('메타데이터 보기'),

        bottom: _mergedMetadata != null

            ? TabBar(

                controller: _tabController,

                isScrollable: true,

                tabs: const [

                  Tab(text: '최종 메타데이터'),

                  Tab(text: 'EXIF'),

                  Tab(text: 'MakerNote'),

                  Tab(text: '파일명 분석'),

                ],

              )

            : null,

      ),

      body: _isPicking

          ? const Center(

              child: Column(

                mainAxisSize: MainAxisSize.min,

                children: [

                  CircularProgressIndicator(),

                  SizedBox(height: 16),

                  Text(

                    '메타데이터 분석 중...',

                    style: TextStyle(color: AppColors.textSecondary),

                  ),

                ],

              ),

            )

          : _mergedMetadata == null

              ? _EmptyState(onPickPhoto: _pickAndAnalyze, error: _errorMessage)

              : Column(

                  children: [

                    if (_photoPath != null)

                      Padding(

                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),

                        child: ClipRRect(

                          borderRadius: BorderRadius.circular(8),

                          child: Image.file(

                            File(_photoPath!),

                            height: 120,

                            width: double.infinity,

                            fit: BoxFit.cover,

                          ),

                        ),

                      ),

                    Padding(

                      padding: const EdgeInsets.all(16),

                      child: OutlinedButton.icon(

                        onPressed: _pickAndAnalyze,

                        icon: const Icon(Icons.refresh),

                        label: const Text('다른 사진 선택'),

                      ),

                    ),

                    Expanded(

                      child: TabBarView(

                        controller: _tabController,

                        children: [

                          _TabContent(

                            title: '최종 메타데이터 (우선순위 적용)',

                            content: _mergedText(),

                            onCopy: () => _copyToClipboard(_mergedText()),

                          ),

                          _TabContent(

                            title: 'EXIF Raw',

                            content: _exifRaw.entries

                                .map((e) => '${e.key}: ${e.value}')

                                .join('\n'),

                            onCopy: () => _copyToClipboard(

                              _exifRaw.entries

                                  .map((e) => '${e.key}: ${e.value}')

                                  .join('\n'),

                            ),

                          ),

                          _TabContent(

                            title: 'MakerNote (Pretty Print)',

                            content: _prettyJson(_makerNoteRaw),

                            onCopy: () => _copyToClipboard(_prettyJson(_makerNoteRaw)),

                            secondary: _ownerNameRaw != null

                                ? 'OwnerName JSON:\n${_prettyJson(_ownerNameRaw)}'

                                : null,

                          ),

                          _TabContent(

                            title: '파일명 분석 결과',

                            content: _filenameResult.entries

                                .map((e) => '${e.key}: ${e.value}')

                                .join('\n'),

                            onCopy: () => _copyToClipboard(

                              _filenameResult.entries

                                  .map((e) => '${e.key}: ${e.value}')

                                  .join('\n'),

                            ),

                          ),

                        ],

                      ),

                    ),

                  ],

                ),

    );

  }

}



class _EmptyState extends StatelessWidget {

  const _EmptyState({required this.onPickPhoto, this.error});



  final VoidCallback onPickPhoto;

  final String? error;



  @override

  Widget build(BuildContext context) {

    return Center(

      child: Padding(

        padding: const EdgeInsets.all(32),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            const Icon(

              Icons.photo_library_outlined,

              size: 64,

              color: AppColors.textSecondary,

            ),

            const SizedBox(height: 16),

            const Text(

              '사진을 선택하면 EXIF, MakerNote,\n파일명 분석 결과를 확인할 수 있습니다.',

              textAlign: TextAlign.center,

              style: TextStyle(color: AppColors.textSecondary),

            ),

            if (error != null) ...[

              const SizedBox(height: 12),

              Text(

                error!,

                style: const TextStyle(color: Colors.redAccent, fontSize: 12),

                textAlign: TextAlign.center,

              ),

            ],

            const SizedBox(height: 24),

            FilledButton.icon(

              onPressed: onPickPhoto,

              icon: const Icon(Icons.add_photo_alternate_outlined),

              label: const Text('사진 선택'),

            ),

          ],

        ),

      ),

    );

  }

}



class _TabContent extends StatelessWidget {

  const _TabContent({

    required this.title,

    required this.content,

    required this.onCopy,

    this.secondary,

  });



  final String title;

  final String content;

  final VoidCallback onCopy;

  final String? secondary;



  @override

  Widget build(BuildContext context) {

    return ListView(

      padding: const EdgeInsets.all(16),

      children: [

        Row(

          children: [

            Expanded(

              child: Text(

                title,

                style: const TextStyle(

                  color: AppColors.textSecondary,

                  fontSize: 12,

                  fontWeight: FontWeight.w600,

                ),

              ),

            ),

            IconButton(

              icon: const Icon(Icons.copy_outlined, size: 18),

              tooltip: '복사',

              onPressed: onCopy,

            ),

          ],

        ),

        Container(

          width: double.infinity,

          padding: const EdgeInsets.all(12),

          decoration: BoxDecoration(

            color: AppColors.surface,

            borderRadius: BorderRadius.circular(8),

          ),

          child: SelectableText(

            content.isEmpty ? '(없음)' : content,

            style: const TextStyle(

              fontSize: 11,

              fontFamily: 'monospace',

              color: AppColors.textPrimary,

              height: 1.6,

            ),

          ),

        ),

        if (secondary != null) ...[

          const SizedBox(height: 16),

          const Text(

            '참고',

            style: TextStyle(

              color: AppColors.textSecondary,

              fontSize: 12,

              fontWeight: FontWeight.w600,

            ),

          ),

          const SizedBox(height: 8),

          Container(

            width: double.infinity,

            padding: const EdgeInsets.all(12),

            decoration: BoxDecoration(

              color: AppColors.surface,

              borderRadius: BorderRadius.circular(8),

            ),

            child: SelectableText(

              secondary!,

              style: const TextStyle(

                fontSize: 11,

                fontFamily: 'monospace',

                color: AppColors.textPrimary,

                height: 1.6,

              ),

            ),

          ),

        ],

      ],

    );

  }

}


