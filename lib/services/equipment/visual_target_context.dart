import '../../core/constants/object_type.dart';
import '../../core/constants/surface_brightness_class.dart';
import '../../data/models/catalog_object.dart';
import '../../data/models/object_imaging_profile.dart';
import '../../data/models/representative_framing_size.dart';
import 'visual_target_suitability.dart';

/// 안시 추천용 천체 컨텍스트 (필터 없음 기준).
class VisualTargetContext {
  const VisualTargetContext({
    required this.object,
    required this.profile,
    required this.framingSize,
    required this.parsedMagnitude,
    required this.visualSurfaceBrightness,
    required this.suitability,
  });

  final CatalogObject object;
  final ObjectImagingProfile profile;
  final RepresentativeFramingSize framingSize;
  final double? parsedMagnitude;
  final SurfaceBrightnessClass visualSurfaceBrightness;
  final VisualTargetSuitabilityInfo suitability;

  ObjectType get scoringObjectType =>
      suitability.effectiveObjectType ?? profile.objectType;

  RepresentativeFramingSize get scoringFramingSize {
    if (suitability.effectiveTargetSizeDegrees != null) {
      return RepresentativeFramingSize.squareDegrees(
        suitability.effectiveTargetSizeDegrees!,
      );
    }
    return framingSize;
  }

  static VisualTargetContext from({
    required CatalogObject object,
    required ObjectImagingProfile profile,
    required RepresentativeFramingSize framingSize,
  }) {
    final suitability = VisualTargetSuitability.analyze(object, profile);
    return VisualTargetContext(
      object: object,
      profile: profile,
      framingSize: framingSize,
      parsedMagnitude: _parseMagnitude(object.magnitude),
      visualSurfaceBrightness: suitability.visualSurfaceBrightness,
      suitability: suitability,
    );
  }

  static double? _parseMagnitude(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.+\-]'), ' ').trim();
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'[-+]?\d+(\.\d+)?').firstMatch(cleaned);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }
}
