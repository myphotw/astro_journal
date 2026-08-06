import '../../data/models/representative_framing_size.dart';

/// angular_size / representative_framing 문자열 파싱.
abstract final class AngularSizeParser {
  static RepresentativeFramingSize? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final arcminMatches =
        RegExp(r"(\d+(?:\.\d+)?)\s*'").allMatches(raw).toList();
    if (arcminMatches.isNotEmpty) {
      final width = double.parse(arcminMatches.first.group(1)!);
      final height = arcminMatches.length >= 2
          ? double.parse(arcminMatches[1].group(1)!)
          : width;
      return RepresentativeFramingSize(
        widthArcmin: width,
        heightArcmin: height,
      );
    }

    final degreeMatch = RegExp(r'(\d+(?:\.\d+)?)\s*°').firstMatch(raw);
    if (degreeMatch != null) {
      final degrees = double.parse(degreeMatch.group(1)!);
      return RepresentativeFramingSize.squareDegrees(degrees);
    }

    return null;
  }
}
