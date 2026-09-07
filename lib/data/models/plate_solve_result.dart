import 'dart:convert';

import '../../services/plate_solve/fits_wcs_parser.dart';

/// Plate Solve 진행 상태.
///
/// 사진 등록·Plate Solve 실행 시 다음과 같이 전이된다.
/// `NONE → PENDING → SUCCESS` 또는 `NONE → PENDING → FAILED`.
enum PlateSolveStatus {
  none,
  pending,
  success,
  failed,
}

/// Plate Solve 모드 (Targeted / Blind).
enum PlateSolveMode {
  targeted,
  blind,
}

/// Plate Solve 결과 — AstroJournal의 표준 WCS(World Coordinate System) 모델.
class PlateSolveResult {
  const PlateSolveResult._({
    required this.status,
    this.centerRa,
    this.centerDec,
    this.rotation,
    this.parity,
    this.pixelScale,
    this.fovWidth,
    this.fovHeight,
    this.imageWidth,
    this.imageHeight,
    this.wcs,
    this.solver,
    this.solvedAt,
    this.errorMessage,
    this.rawWcsJson,
    this.solveMode,
    this.targetObject,
    this.inputRa,
    this.inputDec,
    this.solveTimeMs,
  });

  factory PlateSolveResult.success({
    double? centerRa,
    double? centerDec,
    double? rotation,
    double? parity,
    double? pixelScale,
    double? fovWidth,
    double? fovHeight,
    int? imageWidth,
    int? imageHeight,
    FitsWcsHeader? wcs,
    String? solver,
    DateTime? solvedAt,
    String? rawWcsJson,
    PlateSolveMode? solveMode,
    String? targetObject,
    double? inputRa,
    double? inputDec,
    int? solveTimeMs,
  }) =>
      PlateSolveResult._(
        status: PlateSolveStatus.success,
        centerRa: centerRa,
        centerDec: centerDec,
        rotation: rotation,
        parity: parity,
        pixelScale: pixelScale,
        fovWidth: fovWidth,
        fovHeight: fovHeight,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        wcs: wcs,
        solver: solver,
        solvedAt: solvedAt ?? DateTime.now(),
        rawWcsJson: rawWcsJson,
        solveMode: solveMode,
        targetObject: targetObject,
        inputRa: inputRa,
        inputDec: inputDec,
        solveTimeMs: solveTimeMs,
      );

  factory PlateSolveResult.failure({
    required String errorMessage,
    String? solver,
    PlateSolveMode? solveMode,
    String? targetObject,
    double? inputRa,
    double? inputDec,
    int? solveTimeMs,
  }) =>
      PlateSolveResult._(
        status: PlateSolveStatus.failed,
        solver: solver,
        errorMessage: errorMessage,
        solvedAt: DateTime.now(),
        solveMode: solveMode,
        targetObject: targetObject,
        inputRa: inputRa,
        inputDec: inputDec,
        solveTimeMs: solveTimeMs,
      );

  factory PlateSolveResult.pending({String? solver}) => PlateSolveResult._(
        status: PlateSolveStatus.pending,
        solver: solver,
      );

  final PlateSolveStatus status;

  bool get success => status == PlateSolveStatus.success;

  /// 이미지 중심 적경 (degrees) — calibration `ra` (field center).
  final double? centerRa;

  /// 이미지 중심 적위 (degrees) — calibration `dec`.
  final double? centerDec;

  /// Astrometry.net `orientation` (degrees).
  final double? rotation;

  /// Astrometry.net `parity` (+1 / -1).
  final double? parity;

  /// arcsec/pixel (원본 해상도 기준).
  final double? pixelScale;

  final double? fovWidth;
  final double? fovHeight;
  final int? imageWidth;
  final int? imageHeight;

  /// FITS WCS (CRVAL/CRPIX/CD). 좌표계 오버레이는 이 값을 우선 사용한다.
  final FitsWcsHeader? wcs;

  final String? solver;
  final DateTime? solvedAt;
  final String? errorMessage;

  /// Calibration JSON (+ optional wcs header dump).
  final String? rawWcsJson;

  /// `targeted` / `blind` — 최종 성공(또는 마지막 시도) 모드.
  final PlateSolveMode? solveMode;

  /// Catalog 대상 표시명 (예: M31). Blind면 null.
  final String? targetObject;

  /// Targeted Solve에 사용한 Catalog RA (degrees).
  final double? inputRa;

  /// Targeted Solve에 사용한 Catalog DEC (degrees).
  final double? inputDec;

  /// Solve 소요 시간 (밀리초, 폴백 포함).
  final int? solveTimeMs;

  bool get plateSolved => success;

  bool get hasFullWcs => wcs != null && wcs!.isValid;

  PlateSolveResult copyWith({
    PlateSolveStatus? status,
    double? centerRa,
    double? centerDec,
    double? rotation,
    double? parity,
    double? pixelScale,
    double? fovWidth,
    double? fovHeight,
    int? imageWidth,
    int? imageHeight,
    FitsWcsHeader? wcs,
    String? solver,
    DateTime? solvedAt,
    String? errorMessage,
    String? rawWcsJson,
    PlateSolveMode? solveMode,
    String? targetObject,
    double? inputRa,
    double? inputDec,
    int? solveTimeMs,
  }) {
    return PlateSolveResult._(
      status: status ?? this.status,
      centerRa: centerRa ?? this.centerRa,
      centerDec: centerDec ?? this.centerDec,
      rotation: rotation ?? this.rotation,
      parity: parity ?? this.parity,
      pixelScale: pixelScale ?? this.pixelScale,
      fovWidth: fovWidth ?? this.fovWidth,
      fovHeight: fovHeight ?? this.fovHeight,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      wcs: wcs ?? this.wcs,
      solver: solver ?? this.solver,
      solvedAt: solvedAt ?? this.solvedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      rawWcsJson: rawWcsJson ?? this.rawWcsJson,
      solveMode: solveMode ?? this.solveMode,
      targetObject: targetObject ?? this.targetObject,
      inputRa: inputRa ?? this.inputRa,
      inputDec: inputDec ?? this.inputDec,
      solveTimeMs: solveTimeMs ?? this.solveTimeMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'success': success,
        'centerRa': centerRa,
        'centerDec': centerDec,
        'rotation': rotation,
        'parity': parity,
        'pixelScale': pixelScale,
        'fovWidth': fovWidth,
        'fovHeight': fovHeight,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
        'wcs': wcs?.toJson(),
        'solver': solver,
        'solvedAt': solvedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'rawWcsJson': rawWcsJson,
        'solveMode': solveMode?.name,
        'targetObject': targetObject,
        'inputRa': inputRa,
        'inputDec': inputDec,
        'solveTime': solveTimeMs,
      };

  factory PlateSolveResult.fromJson(Map<String, dynamic> json) {
    final solvedAtStr = _string(json['solvedAt'] ?? json['solved_at']);
    FitsWcsHeader? header;
    final wcsJson = json['wcs'] ?? json['fits_wcs'] ?? json['fitsWcs'];
    if (wcsJson is Map) {
      try {
        header = FitsWcsHeader.fromJson(Map<String, dynamic>.from(wcsJson));
      } catch (_) {
        header = null;
      }
    }
    return PlateSolveResult._(
      status: _statusFromJson(json),
      centerRa: _double(json['centerRa'] ?? json['ra']),
      centerDec: _double(json['centerDec'] ?? json['dec']),
      rotation: _double(json['rotation']),
      parity: _double(json['parity']),
      pixelScale: _double(json['pixelScale'] ?? json['pixel_scale']),
      fovWidth: _double(json['fovWidth'] ?? json['field_width']),
      fovHeight: _double(json['fovHeight'] ?? json['field_height']),
      imageWidth: _int(json['imageWidth'] ?? json['image_width']),
      imageHeight: _int(json['imageHeight'] ?? json['image_height']),
      wcs: header,
      solver: _string(json['solver']),
      solvedAt: solvedAtStr != null ? DateTime.tryParse(solvedAtStr) : null,
      errorMessage: _string(json['errorMessage'] ?? json['error_message']),
      rawWcsJson: _string(json['rawWcsJson'] ?? json['raw_wcs_json']),
      solveMode: _modeFromJson(
        _string(json['solveMode'] ?? json['solve_mode']),
      ),
      targetObject: _string(json['targetObject'] ?? json['target_object']),
      inputRa: _double(json['inputRa'] ?? json['input_ra']),
      inputDec: _double(json['inputDec'] ?? json['input_dec']),
      solveTimeMs: _int(
        json['solveTime'] ?? json['solveTimeMs'] ?? json['solve_time_ms'],
      ),
    );
  }

  static PlateSolveStatus _statusFromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    if (statusName != null) {
      return PlateSolveStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => PlateSolveStatus.none,
      );
    }
    return (json['success'] as bool? ?? false)
        ? PlateSolveStatus.success
        : PlateSolveStatus.failed;
  }

  static PlateSolveMode? _modeFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return PlateSolveMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PlateSolveMode.blind,
    );
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _int(Object? value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String encode(PlateSolveResult result) => jsonEncode(result.toJson());

  static PlateSolveResult? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return PlateSolveResult.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
