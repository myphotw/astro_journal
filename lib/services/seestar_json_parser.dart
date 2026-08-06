import 'dart:convert';

import '../data/models/seestar_metadata.dart';
import 'seestar_parse_analysis_log.dart';

/// Seestar MakerNote / CameraOwnerName JSON 공통 파서.
class SeestarJsonParser {
  const SeestarJsonParser();

  static const _nestedKeys = ['result', 'data', 'metadata', 'info', 'seestar', 'image'];
  static const _objNameKeys = [
    'obj_name',
    'objName',
    'object_name',
    'target',
    'Target',
  ];
  static const _dateKeys = ['date', 'header_date', 'Date', 'capture_date'];
  static const _creatorKeys = ['creator', 'Creator', 'equipment', 'device'];
  static const _stackKeys = ['stack_num', 'stackNum', 'stack', 'frames'];
  static const _expKeys = ['exp_sec', 'expSec', 'exposure', 'exp'];
  static const _totExpKeys = [
    'tot_exp_sec',
    'totExpSec',
    'total_exp_sec',
    'totalExpSec',
    'total_exposure',
  ];

  /// EXIF 태그 원본 문자열에서 JSON `{...}` 블록을 추출한다.
  static String? extractJsonBlock(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    var trimmed = raw.trim();

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is String) {
        return extractJsonBlock(decoded);
      }
      if (decoded is Map || decoded is List) {
        return trimmed;
      }
    } catch (_) {}

    final jsonStart = trimmed.indexOf('{');
    final jsonEnd = trimmed.lastIndexOf('}');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
      return trimmed.substring(jsonStart, jsonEnd + 1);
    }
    if (trimmed.startsWith('{')) return trimmed;
    return null;
  }

  /// [jsonRaw] 문자열을 파싱하여 [SeestarMetadata]를 반환한다.
  ///
  /// [analysisLog]가 주어지면 parse() 단계 로그를 버퍼에 기록한다 (EXIF Debug 화면용).
  SeestarMetadata? parse(
    String? jsonRaw, {
    required String source,
    StringBuffer? analysisLog,
  }) {
    SeestarParseAnalysisLog? trace;
    if (analysisLog != null) {
      trace = SeestarParseAnalysisLog(analysisLog);
    }

    void log(String message) => trace?.writeln(source, message);

    log('parse() entered');

    if (jsonRaw == null || jsonRaw.trim().isEmpty) {
      log('입력 문자열 없음 — 종료');
      return null;
    }

    final jsonBlock = extractJsonBlock(jsonRaw);
    if (jsonBlock == null) {
      log('JSON 블록 추출 실패 — 종료');
      return null;
    }

    try {
      final decoded = jsonDecode(jsonBlock);

      log('jsonDecode 완료');

      if (decoded is! Map) {
        log('JSON이 Map이 아님 — 종료');
        return null;
      }

      log('resolveMap 시작');
      final map = _resolveMap(Map<String, dynamic>.from(decoded));
      log('resolveMap 완료 (keys: ${map.keys.join(", ")})');

      String? creator;
      String? objName;
      String? date;
      int? stackNum;
      double? expSec;
      double? totExpSec;
      double? lat;
      double? lng;

      try {
        log('creator 읽기 시작');
        creator = _asString(_pickValue(map, _creatorKeys));
        log('creator 읽기 완료: ${creator ?? "null"}');
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'creator', e, stack);
        rethrow;
      }

      try {
        log('objName 읽기 시작');
        objName = _normalizeObjName(_asString(_pickValue(map, _objNameKeys)));
        log('objName 읽기 완료: ${objName ?? "null"}');
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'obj_name', e, stack);
        rethrow;
      }

      try {
        log('date 읽기 시작');
        date = _asString(_pickValue(map, _dateKeys));
        log('date 읽기 완료: ${date ?? "null"}');
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'date', e, stack);
        rethrow;
      }

      try {
        final coords = _readCoordinates(map);
        lat = coords.$1;
        lng = coords.$2;
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'lon_lat', e, stack);
        rethrow;
      }

      try {
        stackNum = _asInt(_pickValue(map, _stackKeys));
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'stack_num', e, stack);
        rethrow;
      }

      try {
        expSec = _asDouble(_pickValue(map, _expKeys));
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'exp_sec', e, stack);
        rethrow;
      }

      try {
        totExpSec = _asDouble(_pickValue(map, _totExpKeys));
      } catch (e, stack) {
        _logFieldFailure(trace, source, 'tot_exp_sec', e, stack);
        rethrow;
      }

      log('metadata 생성 시작');
      final metadata = SeestarMetadata(
        creator: creator,
        objName: objName,
        date: date,
        lat: lat,
        lng: lng,
        stackNum: stackNum,
        expSec: expSec,
        totExpSec: totExpSec,
        imgType: _asString(map['img_type'] ?? map['imgType']),
        eqmode: _asInt(map['eqmode']),
        isWide: map['is_wide'] is bool
            ? map['is_wide'] as bool
            : (map['isWide'] is bool ? map['isWide'] as bool : null),
        headerDate: _asString(map['header_date'] ?? map['headerDate']),
        bayerPat: _asString(map['bayer_pat'] ?? map['bayerPat']),
        isSolved: map['is_solved'] is bool
            ? map['is_solved'] as bool
            : (map['isSolved'] is bool ? map['isSolved'] as bool : null),
      );
      log('metadata 생성 완료');

      log('hasCoreMetadata 검사 시작');
      final hasCore = metadata.hasCoreMetadata;
      log('hasCoreMetadata 검사 완료: $hasCore');

      if (!hasCore) {
        log('핵심 필드 없음 — null 반환');
        return null;
      }

      log('parse() 성공');
      return metadata;
    } catch (e, stack) {
      log('예외 발생');
      log('Exception type: ${e.runtimeType}');
      log('message: $e');
      log('stacktrace: $stack');
      return null;
    }
  }

  void _logFieldFailure(
    SeestarParseAnalysisLog? trace,
    String source,
    String fieldName,
    Object e,
    StackTrace stack,
  ) {
    trace?.writeln(source, 'FAILED while reading $fieldName');
    trace?.writeln(source, 'Exception type: ${e.runtimeType}');
    trace?.writeln(source, 'message: $e');
    trace?.writeln(source, 'stacktrace: $stack');
  }

  Map<String, dynamic> _resolveMap(Map<String, dynamic> map) {
    if (_pickValue(map, _objNameKeys) != null ||
        _pickValue(map, _dateKeys) != null ||
        map['lon_lat'] != null ||
        map['lonLat'] != null) {
      return map;
    }

    for (final key in _nestedKeys) {
      final nested = map[key];
      if (nested is Map) {
        final nestedMap = Map<String, dynamic>.from(nested);
        if (_pickValue(nestedMap, _objNameKeys) != null ||
            _pickValue(nestedMap, _dateKeys) != null) {
          return nestedMap;
        }
      }
    }
    return map;
  }

  dynamic _pickValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key];
      }
    }
    return null;
  }

  (double?, double?) _readCoordinates(Map<String, dynamic> map) {
    final lonLat = map['lon_lat'] ?? map['lonLat'] ?? map['gps'];
    if (lonLat is List && lonLat.length >= 2) {
      return (_asDouble(lonLat[1]), _asDouble(lonLat[0]));
    }

    final lat = _asDouble(
      map['lat'] ?? map['latitude'] ?? map['Latitude'],
    );
    final lng = _asDouble(
      map['lng'] ?? map['lon'] ?? map['longitude'] ?? map['Longitude'],
    );
    if (lat != null && lng != null) {
      return (lat, lng);
    }
    return (null, null);
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  String? _normalizeObjName(String? raw) {
    if (raw == null) return null;
    return raw.trim().isEmpty ? null : raw.trim();
  }
}
