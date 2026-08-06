import 'dart:convert';

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

  bool get isValid =>
      crval1.isFinite &&
      crval2.isFinite &&
      crpix1.isFinite &&
      crpix2.isFinite &&
      cd11.isFinite &&
      cd12.isFinite &&
      cd21.isFinite &&
      cd22.isFinite;

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

    return FitsWcsHeader(
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
    );
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
    );
  }

  Map<String, dynamic> toJson() => {
        'crval1': crval1,
        'crval2': crval2,
        'crpix1': crpix1,
        'crpix2': crpix2,
        'cd11': cd11,
        'cd12': cd12,
        'cd21': cd21,
        'cd22': cd22,
        'imageW': imageW,
        'imageH': imageH,
      };

  factory FitsWcsHeader.fromJson(Map<String, dynamic> json) {
    return FitsWcsHeader(
      crval1: (json['crval1'] as num).toDouble(),
      crval2: (json['crval2'] as num).toDouble(),
      crpix1: (json['crpix1'] as num).toDouble(),
      crpix2: (json['crpix2'] as num).toDouble(),
      cd11: (json['cd11'] as num).toDouble(),
      cd12: (json['cd12'] as num).toDouble(),
      cd21: (json['cd21'] as num).toDouble(),
      cd22: (json['cd22'] as num).toDouble(),
      imageW: (json['imageW'] as num?)?.toDouble(),
      imageH: (json['imageH'] as num?)?.toDouble(),
    );
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
