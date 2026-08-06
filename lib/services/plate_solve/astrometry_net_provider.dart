import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/api_test_result.dart';
import '../../data/models/plate_solve_result.dart';
import '../api_key_service.dart';
import '../app_logger.dart';
import '../base_api_service.dart';
import 'fits_wcs_parser.dart';
import 'plate_solve_provider.dart';

/// Astrometry.net (nova.astrometry.net) 비동기 Job API 기반 Plate Solve Provider.
///
/// 흐름:
/// 이미지 전처리 → Login → Upload(스케일/다운샘플 힌트) → Job Polling → Calibration
///
/// 첫 시도 타임아웃이 잦았던 원인과 대응:
/// - 원본 대용량 업로드 + HTTP 30초 제한 → 리사이즈 + 업로드 타임아웃 연장
/// - 스케일 힌트 없음 → FOV 범위·downsample_factor 전달로 서버 처리 가속
/// - 큐 대기에 짧은 job timeout → polling 시간 연장
/// Targeted/Blind 폴백 재시도는 [PlateSolveService]가 담당한다.
class AstrometryNetProvider implements PlateSolveProvider {
  AstrometryNetProvider(this._apiKeyService);

  final ApiKeyService _apiKeyService;

  static const _tag = 'AstrometryNetProvider';
  static const _baseUrl = 'https://nova.astrometry.net/api';

  static const _loginTimeout = Duration(seconds: 45);
  static const _uploadTimeout = Duration(seconds: 180);
  static const _pollHttpTimeout = Duration(seconds: 60);
  static const _submissionPollTimeout = Duration(minutes: 5);
  static const _jobPollTimeout = Duration(minutes: 12);

  /// 업로드용 최대 긴 변(px). 이보다 크면 리사이즈한다.
  static const _uploadMaxEdge = 1600;

  /// 일반 DSO/스마트망원경 FOV 힌트(도). 너무 좁히지 않아 오탐을 줄인다.
  static const _scaleLowerDeg = 0.25;
  static const _scaleUpperDeg = 4.0;

  @override
  String get id => 'astrometry_net';

  @override
  String get displayName => 'Astrometry.net';

  Future<String?> _apiKey() => _apiKeyService.get(ApiKeyType.astrometryNet);

  @override
  Future<bool> get isConfigured async {
    final key = await _apiKey();
    return key != null && key.isNotEmpty;
  }

  @override
  Future<PlateSolveResult> solve({
    required String imagePath,
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    final apiKey = await _apiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return PlateSolveResult.failure(
        errorMessage: 'Astrometry.net API Key가 저장되어 있지 않습니다.',
        solver: id,
      );
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      return PlateSolveResult.failure(
        errorMessage: '이미지 파일을 찾을 수 없습니다.',
        solver: id,
      );
    }

    File? prepared;
    try {
      _report(onProgress, PlateSolveStage.preparing, '이미지 준비 중...');
      prepared = await _prepareUploadImage(file);

      _report(onProgress, PlateSolveStage.uploading, 'Plate Solving...');
      final session = await _login(apiKey);
      final subId = await _upload(
        session,
        prepared,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        centerRa: centerRa,
        centerDec: centerDec,
        searchRadiusDeg: searchRadiusDeg,
        scaleLower: scaleLower,
        scaleUpper: scaleUpper,
      );

      _report(onProgress, PlateSolveStage.solving, '별 패턴 분석 중...');
      final jobId = await _waitForJob(subId);
      final jobStatus = await _waitForJobCompletion(jobId);

      if (jobStatus != 'success') {
        AppLogger.error(_tag, 'Job $jobId finished with status=$jobStatus');
        return PlateSolveResult.failure(
          errorMessage: '이미지에서 별 패턴을 인식하지 못했습니다.',
          solver: id,
        );
      }

      _report(onProgress, PlateSolveStage.calibrating, '좌표 계산 중...');
      final calibration = await _fetchCalibration(jobId);
      final wcsHeader = await _fetchWcsHeader(jobId);

      _report(onProgress, PlateSolveStage.done, 'WCS 생성 중...');
      return _buildResult(
        calibration,
        imageWidth,
        imageHeight,
        uploadImage: prepared,
        wcsHeader: wcsHeader,
      );
    } on TimeoutException catch (e) {
      AppLogger.error(_tag, e);
      return PlateSolveResult.failure(
        errorMessage: 'Plate Solve 처리 시간이 초과되었습니다. 다시 시도해주세요.',
        solver: id,
      );
    } on ApiException catch (e) {
      AppLogger.error(_tag, e);
      return PlateSolveResult.failure(errorMessage: e.message, solver: id);
    } on SocketException catch (e) {
      AppLogger.error(_tag, e);
      return PlateSolveResult.failure(
        errorMessage: '네트워크 오류: ${e.message}',
        solver: id,
      );
    } catch (e, s) {
      AppLogger.error(_tag, e, s);
      return PlateSolveResult.failure(errorMessage: e.toString(), solver: id);
    } finally {
      await _cleanupTemp(prepared, original: file);
    }
  }

  void _report(
    void Function(PlateSolveProgress progress)? onProgress,
    PlateSolveStage stage,
    String message,
  ) {
    AppLogger.info(_tag, message);
    onProgress?.call(PlateSolveProgress(stage, message));
  }

  /// 대용량 원본을 업로드/Solve에 적합한 JPEG로 줄인다.
  Future<File> _prepareUploadImage(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // 디코드 실패 시 원본 업로드 (서버가 처리할 수 있음)
      return source;
    }

    final longest = math.max(decoded.width, decoded.height);
    final needsResize = longest > _uploadMaxEdge;
    final needsReencode = bytes.length > 2 * 1024 * 1024;
    if (!needsResize && !needsReencode) {
      return source;
    }

    img.Image processed = decoded;
    if (needsResize) {
      processed = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? _uploadMaxEdge : null,
        height: decoded.height > decoded.width ? _uploadMaxEdge : null,
        interpolation: img.Interpolation.average,
      );
    }

    final jpg = img.encodeJpg(processed, quality: 88);
    final dir = await getTemporaryDirectory();
    final out = File(
      p.join(
        dir.path,
        'plate_solve_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
    await out.writeAsBytes(jpg, flush: true);
    AppLogger.info(
      _tag,
      'upload prep ${decoded.width}x${decoded.height} '
      '(${bytes.length}B) → ${processed.width}x${processed.height} '
      '(${jpg.length}B)',
    );
    return out;
  }

  Future<void> _cleanupTemp(File? prepared, {required File original}) async {
    if (prepared == null) return;
    if (prepared.path == original.path) return;
    try {
      if (await prepared.exists()) await prepared.delete();
    } catch (_) {}
  }

  Future<String> _login(String apiKey) async {
    final uri = Uri.parse('$_baseUrl/login');
    AppLogger.request('POST', uri.toString());

    final response = await http
        .post(uri, body: {
          'request-json': jsonEncode({'apikey': apiKey}),
        })
        .timeout(_loginTimeout);

    final data = _decode(response);
    final session = data['session'] as String?;
    if (data['status'] != 'success' || session == null) {
      throw ApiException(
        data['errormessage'] as String? ?? 'Astrometry.net 로그인에 실패했습니다.',
        statusCode: response.statusCode,
      );
    }
    return session;
  }

  Future<int> _upload(
    String session,
    File file, {
    int? imageWidth,
    int? imageHeight,
    double? centerRa,
    double? centerDec,
    double? searchRadiusDeg,
    double? scaleLower,
    double? scaleUpper,
  }) async {
    final uri = Uri.parse('$_baseUrl/upload');

    final longest = math.max(imageWidth ?? 0, imageHeight ?? 0);
    final downsample = longest >= 3000
        ? 4
        : longest >= 1600
            ? 2
            : 2;

    final lower = scaleLower ?? _scaleLowerDeg;
    final upper = scaleUpper ?? _scaleUpperDeg;

    final requestJson = <String, dynamic>{
      'session': session,
      'publicly_visible': 'n',
      'allow_modifications': 'n',
      'allow_commercial_use': 'n',
      // Solve 가속 힌트
      'downsample_factor': downsample,
      'scale_units': 'degwidth',
      'scale_type': 'ul',
      'scale_lower': lower,
      'scale_upper': upper > lower ? upper : lower + 0.05,
      // CRPIX를 이미지 중심으로 고정 → CRVAL = field center
      'crpix_center': true,
    };

    if (centerRa != null && centerDec != null) {
      requestJson['center_ra'] = centerRa;
      requestJson['center_dec'] = centerDec;
      requestJson['radius'] = searchRadiusDeg ?? 5.0;
      AppLogger.info(
        _tag,
        'Targeted hints center_ra=$centerRa center_dec=$centerDec '
        'radius=${requestJson['radius']} '
        'scale=[$lower,$upper]',
      );
    } else {
      AppLogger.info(_tag, 'Blind hints scale=[$lower,$upper]');
    }

    final request = http.MultipartRequest('POST', uri)
      ..fields['request-json'] = jsonEncode(requestJson)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    AppLogger.request('POST', uri.toString());
    final streamed = await request.send().timeout(_uploadTimeout);
    final response = await http.Response.fromStream(streamed)
        .timeout(_uploadTimeout);

    final data = _decode(response);
    final subId = data['subid'] as int?;
    if (data['status'] != 'success' || subId == null) {
      throw ApiException(
        data['errormessage'] as String? ?? '이미지 업로드에 실패했습니다.',
        statusCode: response.statusCode,
      );
    }
    return subId;
  }

  Future<int> _waitForJob(int subId) async {
    final deadline = DateTime.now().add(_submissionPollTimeout);
    var interval = const Duration(seconds: 3);
    while (DateTime.now().isBefore(deadline)) {
      final uri = Uri.parse('$_baseUrl/submissions/$subId');
      final response = await http.get(uri).timeout(_pollHttpTimeout);
      final data = _decode(response);

      final jobs = data['jobs'] as List<dynamic>? ?? const [];
      final jobId = jobs.cast<dynamic>().firstWhere(
            (j) => j != null,
            orElse: () => null,
          );
      if (jobId != null) {
        return jobId as int;
      }
      await Future<void>.delayed(interval);
      if (interval.inSeconds < 10) {
        interval = Duration(seconds: interval.inSeconds + 2);
      }
    }
    throw TimeoutException('Job 생성 대기 시간이 초과되었습니다.');
  }

  Future<String> _waitForJobCompletion(int jobId) async {
    final deadline = DateTime.now().add(_jobPollTimeout);
    var interval = const Duration(seconds: 3);
    while (DateTime.now().isBefore(deadline)) {
      final uri = Uri.parse('$_baseUrl/jobs/$jobId');
      final response = await http.get(uri).timeout(_pollHttpTimeout);
      final data = _decode(response);

      final status = data['status'] as String?;
      if (status == 'success' || status == 'failure') {
        return status!;
      }
      await Future<void>.delayed(interval);
      if (interval.inSeconds < 12) {
        interval = Duration(seconds: interval.inSeconds + 2);
      }
    }
    throw TimeoutException('Plate Solve 대기 시간이 초과되었습니다.');
  }

  Future<Map<String, dynamic>> _fetchCalibration(int jobId) async {
    final uri = Uri.parse('$_baseUrl/jobs/$jobId/calibration/');
    final response = await http.get(uri).timeout(_pollHttpTimeout);
    return _decode(response);
  }

  /// `https://nova.astrometry.net/wcs_file/JOBID` — FITS WCS 헤더.
  Future<FitsWcsHeader?> _fetchWcsHeader(int jobId) async {
    try {
      final uri = Uri.parse('https://nova.astrometry.net/wcs_file/$jobId');
      AppLogger.request('GET', uri.toString());
      final response = await http.get(uri).timeout(_pollHttpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.info(_tag, 'wcs_file HTTP ${response.statusCode}');
        return null;
      }
      final header = FitsWcsHeader.tryParse(response.bodyBytes);
      if (header == null) {
        AppLogger.info(_tag, 'wcs_file parse failed job=$jobId');
      } else {
        AppLogger.info(
          _tag,
          'wcs_file OK CRVAL=(${header.crval1},${header.crval2}) '
          'CRPIX=(${header.crpix1},${header.crpix2}) '
          'CD=[${header.cd11},${header.cd12};${header.cd21},${header.cd22}]',
        );
      }
      return header;
    } catch (e) {
      AppLogger.info(_tag, 'wcs_file fetch failed: $e');
      return null;
    }
  }

  PlateSolveResult _buildResult(
    Map<String, dynamic> calibration,
    int? imageWidth,
    int? imageHeight, {
    required File uploadImage,
    FitsWcsHeader? wcsHeader,
  }) {
    final ra = (calibration['ra'] as num?)?.toDouble();
    final dec = (calibration['dec'] as num?)?.toDouble();
    final orientation = (calibration['orientation'] as num?)?.toDouble();
    final parity = (calibration['parity'] as num?)?.toDouble();
    var pixScale = (calibration['pixscale'] as num?)?.toDouble();

    var uploadW = 0.0;
    var uploadH = 0.0;
    try {
      final uploadBytes = uploadImage.readAsBytesSync();
      final uploadDecoded = img.decodeImage(uploadBytes);
      if (uploadDecoded != null) {
        uploadW = uploadDecoded.width.toDouble();
        uploadH = uploadDecoded.height.toDouble();
      }
    } catch (_) {}

    // 업로드 이미지가 리사이즈된 경우 pixscale·WCS를 원본 해상도로 환산
    FitsWcsHeader? scaledWcs = wcsHeader;
    if (imageWidth != null &&
        imageHeight != null &&
        imageWidth > 0 &&
        imageHeight > 0 &&
        uploadW > 0 &&
        uploadH > 0) {
      final scaleFactor = uploadW / imageWidth;
      if (pixScale != null) {
        pixScale = pixScale * scaleFactor;
        AppLogger.info(
          _tag,
          'pixscale rescale uploadW=$uploadW origW=$imageWidth '
          'factor=${scaleFactor.toStringAsFixed(4)} '
          '→ ${pixScale.toStringAsFixed(4)}"/px',
        );
      }
      if (wcsHeader != null) {
        scaledWcs = wcsHeader.scaleToOriginal(
          uploadWidth: uploadW,
          uploadHeight: uploadH,
          originalWidth: imageWidth.toDouble(),
          originalHeight: imageHeight.toDouble(),
        );
      }
    }

    double? fovWidth;
    double? fovHeight;
    if (pixScale != null) {
      if (imageWidth != null) fovWidth = pixScale * imageWidth / 3600.0;
      if (imageHeight != null) fovHeight = pixScale * imageHeight / 3600.0;
    }

    return PlateSolveResult.success(
      centerRa: ra,
      centerDec: dec,
      rotation: orientation,
      parity: parity,
      pixelScale: pixScale,
      fovWidth: fovWidth,
      fovHeight: fovHeight,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      wcs: scaledWcs,
      solver: id,
      solvedAt: DateTime.now(),
      rawWcsJson: jsonEncode({
        ...calibration,
        if (scaledWcs != null) 'fits_wcs': scaledWcs.toJson(),
      }),
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    AppLogger.response(
      response.request?.url.toString() ?? _baseUrl,
      response.statusCode,
      response.body,
      elapsedMs: 0,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    if (response.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      throw ApiException('응답 파싱에 실패했습니다.', statusCode: response.statusCode);
    }
  }

  @override
  Future<ApiTestResult> testConnection() async {
    final apiKey = await _apiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return ApiTestResult.failure(
        message: 'Astrometry.net API Key가 저장되어 있지 않습니다.',
      );
    }

    final sw = Stopwatch()..start();
    try {
      final session = await _login(apiKey);
      sw.stop();
      AppLogger.info(_tag, 'Test OK (${sw.elapsedMilliseconds}ms)');
      return ApiTestResult.success(
        statusCode: 200,
        responseTimeMs: sw.elapsedMilliseconds,
        data: {'session': session},
      );
    } on ApiException catch (e) {
      sw.stop();
      AppLogger.error(_tag, e);
      return ApiTestResult.failure(message: e.message, statusCode: e.statusCode);
    } catch (e, s) {
      sw.stop();
      AppLogger.error(_tag, e, s);
      return ApiTestResult.failure(message: e.toString());
    }
  }
}
