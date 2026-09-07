import 'dart:convert';
import 'dart:math' as math;

/// SIP distortion coefficients attached to a TAN-SIP WCS solution.
///
/// Coefficient keys use the canonical `i_j` form, for example `2_0`.
class FitsSipDistortion {
  const FitsSipDistortion({
    this.aOrder,
    this.bOrder,
    this.apOrder,
    this.bpOrder,
    this.a = const {},
    this.b = const {},
    this.ap = const {},
    this.bp = const {},
  });

  final int? aOrder;
  final int? bOrder;
  final int? apOrder;
  final int? bpOrder;
  final Map<String, double> a;
  final Map<String, double> b;
  final Map<String, double> ap;
  final Map<String, double> bp;

  bool get hasForward => a.isNotEmpty || b.isNotEmpty;
  bool get hasInverse => ap.isNotEmpty || bp.isNotEmpty;

  bool get isValid =>
      _validSet(a, aOrder) &&
      _validSet(b, bOrder) &&
      _validSet(ap, apOrder) &&
      _validSet(bp, bpOrder) &&
      (hasForward || hasInverse);

  double evaluateA(double u, double v) => _evaluate(a, u, v);
  double evaluateB(double u, double v) => _evaluate(b, u, v);
  double evaluateAp(double u, double v) => _evaluate(ap, u, v);
  double evaluateBp(double u, double v) => _evaluate(bp, u, v);

  FitsSipDistortion scale(double scaleX, double scaleY) => FitsSipDistortion(
        aOrder: aOrder,
        bOrder: bOrder,
        apOrder: apOrder,
        bpOrder: bpOrder,
        a: _scaleCoefficients(
          a,
          outputScale: scaleX,
          scaleX: scaleX,
          scaleY: scaleY,
        ),
        b: _scaleCoefficients(
          b,
          outputScale: scaleY,
          scaleX: scaleX,
          scaleY: scaleY,
        ),
        ap: _scaleCoefficients(
          ap,
          outputScale: scaleX,
          scaleX: scaleX,
          scaleY: scaleY,
        ),
        bp: _scaleCoefficients(
          bp,
          outputScale: scaleY,
          scaleX: scaleX,
          scaleY: scaleY,
        ),
      );

  Map<String, dynamic> toJson() => {
    'a_order': aOrder,
    'b_order': bOrder,
    'ap_order': apOrder,
    'bp_order': bpOrder,
    'a': a,
    'b': b,
    'ap': ap,
    'bp': bp,
  };

  factory FitsSipDistortion.fromJson(Map<String, dynamic> json) {
    final result = FitsSipDistortion(
      aOrder: _int(json['a_order'] ?? json['aOrder']),
      bOrder: _int(json['b_order'] ?? json['bOrder']),
      apOrder: _int(json['ap_order'] ?? json['apOrder']),
      bpOrder: _int(json['bp_order'] ?? json['bpOrder']),
      a: _coefficientMap(json['a']),
      b: _coefficientMap(json['b']),
      ap: _coefficientMap(json['ap']),
      bp: _coefficientMap(json['bp']),
    );
    if (!result.isValid) {
      throw const FormatException('SIP coefficients are malformed.');
    }
    return result;
  }

  static bool _validSet(Map<String, double> values, int? order) {
    if (values.isEmpty) return true;
    if (order == null || order < 0) return false;
    for (final entry in values.entries) {
      final powers = _powers(entry.key);
      if (powers == null ||
          powers.$1 + powers.$2 > order ||
          !entry.value.isFinite) {
        return false;
      }
    }
    return true;
  }

  static double _evaluate(
    Map<String, double> coefficients,
    double u,
    double v,
  ) {
    var result = 0.0;
    for (final entry in coefficients.entries) {
      final powers = _powers(entry.key);
      if (powers == null) return double.nan;
      result += (entry.value *
              math.pow(u, powers.$1) *
              math.pow(v, powers.$2))
          .toDouble();
    }
    return result;
  }

  static Map<String, double> _scaleCoefficients(
    Map<String, double> source, {
    required double outputScale,
    required double scaleX,
    required double scaleY,
  }) {
    final result = <String, double>{};
    for (final entry in source.entries) {
      final powers = _powers(entry.key)!;
      result[entry.key] = (outputScale *
              entry.value /
              math.pow(scaleX, powers.$1) /
              math.pow(scaleY, powers.$2))
          .toDouble();
    }
    return result;
  }

  static Map<String, double> _coefficientMap(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const FormatException('SIP coefficient set is not an object.');
    }
    final result = <String, double>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (_powers(key) == null) {
        throw FormatException('Invalid SIP coefficient key: $key');
      }
      final value = _double(entry.value);
      if (value == null || !value.isFinite) {
        throw FormatException('Invalid SIP coefficient value: $key');
      }
      result[key] = value;
    }
    return result;
  }

  static (int, int)? _powers(String key) {
    final match = RegExp(r'^(\d+)_(\d+)$').firstMatch(key);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static int? _int(Object? value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}

/// Astrometry.net `wcs_file` (FITS header) 파서.
///
/// CRVAL / CRPIX / CD 행렬을 추출해 원본 픽셀 좌표 변환에 사용한다.
class FitsWcsHeader {
  const FitsWcsHeader({
    required this.crval1,
    required this.crval2,
    required this.crpix1,
    required this.crpix2,
    required this.cd11,
    required this.cd12,
    required this.cd21,
    required this.cd22,
    this.imageW,
    this.imageH,
    this.schemaVersion,
    this.ctype1,
    this.ctype2,
    this.cunit1,
    this.cunit2,
    this.radesys,
    this.equinox,
    this.lonpole,
    this.latpole,
    this.sip,
  });

  /// 참조점 적경 (degrees).
  final double crval1;

  /// 참조점 적위 (degrees).
  final double crval2;

  /// 참조 픽셀 X (FITS 1-based).
  final double crpix1;

  /// 참조 픽셀 Y (FITS 1-based).
  final double crpix2;

  final double cd11;
  final double cd12;
  final double cd21;
  final double cd22;

  final double? imageW;
  final double? imageH;

  final int? schemaVersion;
  final String? ctype1;
  final String? ctype2;
  final String? cunit1;
  final String? cunit2;
  final String? radesys;
  final double? equinox;
  final double? lonpole;
  final double? latpole;
  final FitsSipDistortion? sip;

  double? get rasterWidth => imageW;
  double? get rasterHeight => imageH;

  bool get usesSip =>
      (ctype1?.toUpperCase().contains('-SIP') ?? false) ||
      (ctype2?.toUpperCase().contains('-SIP') ?? false);

  bool get supportsProjection {
    if (ctype1 == null && ctype2 == null) return true;
    final first = ctype1?.toUpperCase() ?? '';
    final second = ctype2?.toUpperCase() ?? '';
    final isTan = first.startsWith('RA---TAN') && second.startsWith('DEC--TAN');
    if (!isTan) return false;
    return !usesSip || (sip?.isValid ?? false);
  }

  String get sipInverseMode => !usesSip
      ? 'none'
      : (sip?.hasInverse == true ? 'ap_bp' : 'iterative_ab');

  bool get isValid =>
      crval1.isFinite &&
      crval2.isFinite &&
      crpix1.isFinite &&
      crpix2.isFinite &&
      cd11.isFinite &&
      cd12.isFinite &&
      cd21.isFinite &&
      cd22.isFinite &&
      (cd11 * cd22 - cd12 * cd21).abs() >= 1e-30 &&
      supportsProjection;

  /// FITS 바이너리 또는 텍스트 헤더에서 파싱.
  static FitsWcsHeader? tryParse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final text = _headerText(bytes);
    if (text == null || text.isEmpty) return null;
    return tryParseText(text);
  }

  static FitsWcsHeader? tryParseText(String text) {
    final cards = <String, String>{};
    // 80-char FITS cards or newline-separated KEY = VALUE
    if (text.contains('\n') && !text.trimLeft().startsWith('SIMPLE')) {
      for (final line in const LineSplitter().convert(text)) {
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim().toUpperCase();
        var val = line.substring(eq + 1).trim();
        final slash = val.indexOf('/');
        if (slash >= 0) val = val.substring(0, slash).trim();
        cards[key] = val.replaceAll("'", '').trim();
      }
    } else {
      // Fixed 80-byte cards
      final padded = text.padRight((text.length + 79) ~/ 80 * 80);
      for (var i = 0; i + 80 <= padded.length; i += 80) {
        final card = padded.substring(i, i + 80);
        if (card.startsWith('END')) break;
        final eq = card.indexOf('=');
        if (eq <= 0) continue;
        final key = card.substring(0, eq).trim().toUpperCase();
        var val = card.substring(eq + 1).trim();
        final slash = val.indexOf('/');
        if (slash >= 0) val = val.substring(0, slash).trim();
        cards[key] = val.replaceAll("'", '').trim();
      }
    }

    double? num(String key) => double.tryParse(cards[key] ?? '');

    // CD matrix preferred; else PC * CDELT
    var cd11 = num('CD1_1');
    var cd12 = num('CD1_2');
    var cd21 = num('CD2_1');
    var cd22 = num('CD2_2');
    if (cd11 == null || cd22 == null) {
      final cdelt1 = num('CDELT1');
      final cdelt2 = num('CDELT2');
      final pc11 = num('PC1_1') ?? 1.0;
      final pc12 = num('PC1_2') ?? 0.0;
      final pc21 = num('PC2_1') ?? 0.0;
      final pc22 = num('PC2_2') ?? 1.0;
      if (cdelt1 != null && cdelt2 != null) {
        cd11 = pc11 * cdelt1;
        cd12 = pc12 * cdelt1;
        cd21 = pc21 * cdelt2;
        cd22 = pc22 * cdelt2;
      }
    }

    final crval1 = num('CRVAL1');
    final crval2 = num('CRVAL2');
    final crpix1 = num('CRPIX1');
    final crpix2 = num('CRPIX2');
    if (crval1 == null ||
        crval2 == null ||
        crpix1 == null ||
        crpix2 == null ||
        cd11 == null ||
        cd12 == null ||
        cd21 == null ||
        cd22 == null) {
      return null;
    }

    FitsSipDistortion? sip;
    final a = <String, double>{};
    final b = <String, double>{};
    final ap = <String, double>{};
    final bp = <String, double>{};
    for (final entry in cards.entries) {
      final match = RegExp(r'^(A|B|AP|BP)_(\d+)_(\d+)$').firstMatch(entry.key);
      if (match == null) continue;
      final coefficient = double.tryParse(entry.value);
      if (coefficient == null || !coefficient.isFinite) return null;
      final key = '${match.group(2)}_${match.group(3)}';
      switch (match.group(1)) {
        case 'A':
          a[key] = coefficient;
          break;
        case 'B':
          b[key] = coefficient;
          break;
        case 'AP':
          ap[key] = coefficient;
          break;
        case 'BP':
          bp[key] = coefficient;
          break;
      }
    }
    if (a.isNotEmpty || b.isNotEmpty || ap.isNotEmpty || bp.isNotEmpty) {
      sip = FitsSipDistortion(
        aOrder: num('A_ORDER')?.toInt(),
        bOrder: num('B_ORDER')?.toInt(),
        apOrder: num('AP_ORDER')?.toInt(),
        bpOrder: num('BP_ORDER')?.toInt(),
        a: a,
        b: b,
        ap: ap,
        bp: bp,
      );
      if (!sip.isValid) return null;
    }

    final result = FitsWcsHeader(
      crval1: crval1,
      crval2: crval2,
      crpix1: crpix1,
      crpix2: crpix2,
      cd11: cd11,
      cd12: cd12,
      cd21: cd21,
      cd22: cd22,
      imageW: num('IMAGEW') ?? num('NAXIS1'),
      imageH: num('IMAGEH') ?? num('NAXIS2'),
      ctype1: cards['CTYPE1'],
      ctype2: cards['CTYPE2'],
      cunit1: cards['CUNIT1'],
      cunit2: cards['CUNIT2'],
      radesys: cards['RADESYS'],
      equinox: num('EQUINOX'),
      lonpole: num('LONPOLE'),
      latpole: num('LATPOLE'),
      sip: sip,
    );
    return result.isValid ? result : null;
  }

  /// 업로드(솔브) 해상도 → 원본 해상도로 CD/CRPIX 환산.
  FitsWcsHeader scaleToOriginal({
    required double uploadWidth,
    required double uploadHeight,
    required double originalWidth,
    required double originalHeight,
  }) {
    if (uploadWidth <= 0 ||
        uploadHeight <= 0 ||
        originalWidth <= 0 ||
        originalHeight <= 0) {
      return this;
    }
    final sx = originalWidth / uploadWidth;
    final sy = originalHeight / uploadHeight;
    if ((sx - 1).abs() < 1e-9 && (sy - 1).abs() < 1e-9) return this;

    // FITS 픽셀 중심 기준: (crpix - 0.5) * scale + 0.5
    return FitsWcsHeader(
      crval1: crval1,
      crval2: crval2,
      crpix1: (crpix1 - 0.5) * sx + 0.5,
      crpix2: (crpix2 - 0.5) * sy + 0.5,
      cd11: cd11 / sx,
      cd12: cd12 / sy,
      cd21: cd21 / sx,
      cd22: cd22 / sy,
      imageW: originalWidth,
      imageH: originalHeight,
      schemaVersion: schemaVersion,
      ctype1: ctype1,
      ctype2: ctype2,
      cunit1: cunit1,
      cunit2: cunit2,
      radesys: radesys,
      equinox: equinox,
      lonpole: lonpole,
      latpole: latpole,
      sip: sip?.scale(sx, sy),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'ctype1': ctype1,
        'ctype2': ctype2,
        'cunit1': cunit1,
        'cunit2': cunit2,
        'radesys': radesys,
        'equinox': equinox,
        'lonpole': lonpole,
        'latpole': latpole,
        'crval1': crval1,
        'crval2': crval2,
        'crpix1': crpix1,
        'crpix2': crpix2,
        'cd11': cd11,
        'cd12': cd12,
        'cd21': cd21,
        'cd22': cd22,
        'raster_width': imageW,
        'raster_height': imageH,
        'sip': sip?.toJson(),
      };

  factory FitsWcsHeader.fromJson(Map<String, dynamic> json) {
    final sipJson = json['sip'];
    final result = FitsWcsHeader(
      crval1: _requiredDouble(json, 'crval1'),
      crval2: _requiredDouble(json, 'crval2'),
      crpix1: _requiredDouble(json, 'crpix1'),
      crpix2: _requiredDouble(json, 'crpix2'),
      cd11: _requiredDouble(json, 'cd11'),
      cd12: _requiredDouble(json, 'cd12'),
      cd21: _requiredDouble(json, 'cd21'),
      cd22: _requiredDouble(json, 'cd22'),
      imageW: _optionalDouble(json['raster_width'] ?? json['imageW']),
      imageH: _optionalDouble(json['raster_height'] ?? json['imageH']),
      schemaVersion: _optionalInt(json['schema_version'] ?? json['schemaVersion']),
      ctype1: _optionalString(json['ctype1']),
      ctype2: _optionalString(json['ctype2']),
      cunit1: _optionalString(json['cunit1']),
      cunit2: _optionalString(json['cunit2']),
      radesys: _optionalString(json['radesys']),
      equinox: _optionalDouble(json['equinox']),
      lonpole: _optionalDouble(json['lonpole']),
      latpole: _optionalDouble(json['latpole']),
      sip: sipJson is Map
          ? FitsSipDistortion.fromJson(Map<String, dynamic>.from(sipJson))
          : null,
    );
    if (!result.isValid) {
      throw const FormatException('WCS header is malformed or unsupported.');
    }
    return result;
  }

  static double _requiredDouble(Map<String, dynamic> json, String key) {
    final value = _optionalDouble(json[key]);
    if (value == null || !value.isFinite) {
      throw FormatException('WCS has no valid $key.');
    }
    return value;
  }

  static double? _optionalDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int? _optionalInt(Object? value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '');

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _headerText(List<int> bytes) {
    // ASCII text WCS
    if (bytes.length >= 6) {
      final head = ascii.decode(bytes.take(8).toList(), allowInvalid: true);
      if (head.startsWith('SIMPLE') || head.contains('CRVAL')) {
        // May be full FITS — extract header blocks
        return _extractFitsHeaderAscii(bytes) ??
            utf8.decode(bytes, allowMalformed: true);
      }
    }
    return _extractFitsHeaderAscii(bytes);
  }

  static String? _extractFitsHeaderAscii(List<int> bytes) {
    if (bytes.length < 80) return null;
    final buffer = StringBuffer();
    var offset = 0;
    while (offset + 80 <= bytes.length) {
      final cardBytes = bytes.sublist(offset, offset + 80);
      final card = ascii.decode(cardBytes, allowInvalid: true);
      buffer.write(card);
      offset += 80;
      if (card.startsWith('END')) break;
      // FITS header blocks are 2880 bytes; continue until END
      if (offset % 2880 == 0 && !buffer.toString().contains('END')) {
        // continue into next block
      }
      // Safety: max 20 blocks
      if (offset > 2880 * 20) break;
    }
    final text = buffer.toString();
    if (!text.contains('CRVAL1') || !text.contains('CRPIX1')) return null;
    return text;
  }
}
