import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pure-Dart RGBA → PNG encoder (isolate-safe, no dart:ui).
class LightPollutionTilePng {
  LightPollutionTilePng._();

  static Uint8List encodeRgba({
    required int width,
    required int height,
    required Uint8List rgba,
  }) {
    assert(rgba.length == width * height * 4);

    final raw = Uint8List((width * 4 + 1) * height);
    for (var y = 0; y < height; y++) {
      final src = y * width * 4;
      final dst = y * (width * 4 + 1);
      raw[dst] = 0; // filter: None
      raw.setRange(dst + 1, dst + 1 + width * 4, rgba, src);
    }

    final compressed = const ZLibEncoder().encode(raw);

    final bytes = BytesBuilder(copy: false);
    bytes.add(const [137, 80, 78, 71, 13, 10, 26, 10]); // PNG signature
    _writeChunk(bytes, 'IHDR', _ihdr(width, height));
    _writeChunk(bytes, 'IDAT', Uint8List.fromList(compressed));
    _writeChunk(bytes, 'IEND', Uint8List(0));
    return bytes.toBytes();
  }

  static Uint8List _ihdr(int width, int height) {
    final data = ByteData(13);
    data.setUint32(0, width);
    data.setUint32(4, height);
    data.setUint8(8, 8); // bit depth
    data.setUint8(9, 6); // RGBA
    data.setUint8(10, 0); // compression
    data.setUint8(11, 0); // filter
    data.setUint8(12, 0); // interlace
    return data.buffer.asUint8List();
  }

  static void _writeChunk(BytesBuilder out, String type, Uint8List data) {
    final typeBytes = type.codeUnits;
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);

    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setRange(0, typeBytes.length, typeBytes);
    crcInput.setRange(typeBytes.length, crcInput.length, data);
    final crc = getCrc32(crcInput);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    out.add(crcBytes.buffer.asUint8List());
  }
}
