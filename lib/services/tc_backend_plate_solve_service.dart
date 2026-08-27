import 'dart:async';
import 'dart:convert';

import '../data/models/plate_solve_result.dart';
import 'plate_solve/plate_solve_provider.dart';
import 'tc_backend_external_api_client.dart';

class TcBackendPlateSolveService {
  TcBackendPlateSolveService({
    required TcBackendExternalApiClient client,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollDuration = const Duration(minutes: 5),
    Future<void> Function(Duration)? delay,
  }) : _client = client,
       _delay = delay ?? Future<void>.delayed;

  final TcBackendExternalApiClient _client;
  final Duration pollInterval;
  final Duration maxPollDuration;
  final Future<void> Function(Duration) _delay;

  Future<PlateSolveResult> solve({
    required int commonFileId,
    void Function(PlateSolveProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const PlateSolveProgress(
        PlateSolveStage.uploading,
        'Backend Plate Solve 요청 중…',
      ),
    );
    var job = await _client.postMap(
      '/api/astro/plate-solve',
      body: {'common_file_id': commonFileId},
    );
    final jobId = _requiredString(job, 'job_id');
    final responseFileId = _requiredInt(job, 'common_file_id');
    if (responseFileId != commonFileId) {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: 'Plate Solve 응답의 파일 ID가 요청과 일치하지 않습니다.',
      );
    }

    final started = DateTime.now();
    while (true) {
      final status = _requiredString(job, 'status').toUpperCase();
      switch (status) {
        case 'WAITING':
          onProgress?.call(
            const PlateSolveProgress(
              PlateSolveStage.uploading,
              'Plate Solve 대기 중…',
            ),
          );
          break;
        case 'PROCESSING':
          onProgress?.call(
            const PlateSolveProgress(PlateSolveStage.solving, 'Plate Solving…'),
          );
          break;
        case 'COMPLETED':
          return _completed(job);
        case 'FAILED':
          throw const TcBackendExternalApiException(
            code: TcBackendExternalApiErrorCode.providerError,
            message: 'Backend Plate Solve에 실패했습니다.',
          );
        default:
          throw const TcBackendExternalApiException(
            code: TcBackendExternalApiErrorCode.malformedResponse,
            message: '알 수 없는 Plate Solve 상태입니다.',
          );
      }

      if (DateTime.now().difference(started) >= maxPollDuration) {
        throw const TcBackendExternalApiException(
          code: TcBackendExternalApiErrorCode.timeout,
          message: 'Plate Solve 처리 시간이 초과되었습니다.',
        );
      }
      await _delay(pollInterval);
      job = await _client.getMap('/api/astro/plate-solve/$jobId');
      if (_requiredInt(job, 'common_file_id') != commonFileId) {
        throw const TcBackendExternalApiException(
          code: TcBackendExternalApiErrorCode.malformedResponse,
          message: 'Plate Solve Job의 파일 ID가 요청과 일치하지 않습니다.',
        );
      }
    }
  }

  PlateSolveResult _completed(Map<String, dynamic> job) {
    final raw = job['result'];
    if (raw is! Map) {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: '완료된 Plate Solve 응답에 결과가 없습니다.',
      );
    }
    final result = Map<String, dynamic>.from(raw);
    return PlateSolveResult.success(
      centerRa: _optionalDouble(result['ra']),
      centerDec: _optionalDouble(result['dec']),
      rotation: _optionalDouble(result['rotation']),
      pixelScale: _optionalDouble(result['pixel_scale']),
      fovWidth: _optionalDouble(result['field_width']),
      fovHeight: _optionalDouble(result['field_height']),
      parity: _optionalDouble(result['parity']),
      solver: _requiredString(job, 'provider'),
      rawWcsJson: jsonEncode(result),
      solveMode: PlateSolveMode.blind,
    );
  }

  String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: 'Plate Solve 응답에 $key 값이 없습니다.',
      );
    }
    return value;
  }

  int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is num && value.toInt() > 0) return value.toInt();
    throw TcBackendExternalApiException(
      code: TcBackendExternalApiErrorCode.malformedResponse,
      message: 'Plate Solve 응답에 유효한 $key 값이 없습니다.',
    );
  }

  double? _optionalDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
