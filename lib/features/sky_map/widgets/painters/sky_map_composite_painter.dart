import 'package:flutter/material.dart';

import '../../../../data/models/sky_map_render_object.dart';
import 'catalog_object_painter.dart';
import 'constellation_painter.dart';
import 'fov_painter.dart';
import 'sky_map_background_painter.dart';
import 'star_painter.dart';

/// Sky Map Layer 합성 (아래 → 위).
///
/// 1. Background
/// 2. Constellation Line
/// 3. Bright Star
/// 4. Catalog Object Shape
/// 5. FOV Overlay
class SkyMapCompositePainter extends CustomPainter {
  SkyMapCompositePainter({
    required this.constellations,
    required this.stars,
    required this.objects,
    required this.selectedId,
    required this.fovCorners,
    required this.showConstellations,
    required this.showStars,
    required this.showLabels,
  });

  final List<SkyMapConstellationRender> constellations;
  final List<SkyMapStarRender> stars;
  final List<SkyMapRenderObject> objects;
  final String? selectedId;
  final List<Offset> fovCorners;
  final bool showConstellations;
  final bool showStars;
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    const SkyMapBackgroundPainter().paint(canvas, size);

    if (showConstellations && constellations.isNotEmpty) {
      ConstellationPainter(constellations: constellations).paint(canvas, size);
    }

    if (showStars && stars.isNotEmpty) {
      StarPainter(stars: stars, showLabels: showLabels).paint(canvas, size);
    }

    CatalogObjectPainter(
      objects: objects,
      selectedId: selectedId,
      showLabels: showLabels,
    ).paint(canvas, size);

    if (fovCorners.length == 4) {
      FovPainter(corners: fovCorners).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant SkyMapCompositePainter oldDelegate) {
    return oldDelegate.constellations != constellations ||
        oldDelegate.stars != stars ||
        oldDelegate.objects != objects ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.fovCorners != fovCorners ||
        oldDelegate.showConstellations != showConstellations ||
        oldDelegate.showStars != showStars ||
        oldDelegate.showLabels != showLabels;
  }
}
