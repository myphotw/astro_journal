import 'package:flutter/material.dart';

import '../../../../data/models/sky_map_render_object.dart';
import '../../../../data/models/site_horizon_profile.dart';
import '../../../../services/sky_map_milky_way_service.dart';
import 'catalog_object_painter.dart';
import 'constellation_painter.dart';
import 'fov_painter.dart';
import 'milky_way_painter.dart';
import 'observation_site_horizon_painter.dart';
import 'sky_map_background_painter.dart';
import 'star_painter.dart';

/// Sky Map Layer 합성 (아래 → 위).
///
/// 1. Atmosphere / ground
/// 2. Milky Way
/// 3. Observation-site horizon mask
/// 4. Alt/Az grid and coordinate labels
/// 5. Constellation Line
/// 6. Bright Star
/// 7. Catalog Object Shape
/// 8. FOV Overlay
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
    required this.centerAltitudeDeg,
    required this.centerAzimuthDeg,
    required this.viewHeightDeg,
    required this.sunAltitudeDeg,
    required this.sunAzimuthDeg,
    this.milkyWay = const SkyMapMilkyWayHorizontalMesh.empty(),
    this.showMilkyWay = true,
    this.observationSiteHorizonProfile = const SiteHorizonProfile(),
    this.showObservationSiteHorizon = true,
  });

  final List<SkyMapConstellationRender> constellations;
  final List<SkyMapStarRender> stars;
  final List<SkyMapRenderObject> objects;
  final String? selectedId;
  final List<Offset> fovCorners;
  final bool showConstellations;
  final bool showStars;
  final bool showLabels;
  final double centerAltitudeDeg;
  final double centerAzimuthDeg;
  final double viewHeightDeg;
  final double sunAltitudeDeg;
  final double sunAzimuthDeg;
  final SkyMapMilkyWayHorizontalMesh milkyWay;
  final bool showMilkyWay;
  final SiteHorizonProfile observationSiteHorizonProfile;
  final bool showObservationSiteHorizon;

  @override
  void paint(Canvas canvas, Size size) {
    final occupiedLabels = <Rect>[];

    final background = SkyMapBackgroundPainter(
      centerAltitudeDeg: centerAltitudeDeg,
      centerAzimuthDeg: centerAzimuthDeg,
      viewHeightDeg: viewHeightDeg,
      sunAltitudeDeg: sunAltitudeDeg,
      sunAzimuthDeg: sunAzimuthDeg,
      occupiedLabels: occupiedLabels,
    );
    background.paintAtmosphereLayer(canvas, size);

    if (showMilkyWay && !milkyWay.isEmpty) {
      MilkyWayPainter(
        mesh: milkyWay,
        centerAltitudeDeg: centerAltitudeDeg,
        centerAzimuthDeg: centerAzimuthDeg,
        viewHeightDeg: viewHeightDeg,
        sunAltitudeDeg: sunAltitudeDeg,
      ).paint(canvas, size);
    }

    if (showObservationSiteHorizon &&
        observationSiteHorizonProfile.hasRestrictions) {
      ObservationSiteHorizonPainter(
        profile: observationSiteHorizonProfile,
        centerAltitudeDeg: centerAltitudeDeg,
        centerAzimuthDeg: centerAzimuthDeg,
        viewHeightDeg: viewHeightDeg,
      ).paint(canvas, size);
    }

    background.paintCoordinateLayer(canvas, size);

    if (showConstellations && constellations.isNotEmpty) {
      ConstellationPainter(
        constellations: constellations,
        viewHeightDeg: viewHeightDeg,
        occupiedLabels: occupiedLabels,
      ).paint(canvas, size);
    }

    if (showStars && stars.isNotEmpty) {
      StarPainter(
        stars: stars,
        showLabels: showLabels,
        viewHeightDeg: viewHeightDeg,
        occupiedLabels: occupiedLabels,
      ).paint(canvas, size);
    }

    CatalogObjectPainter(
      objects: objects,
      selectedId: selectedId,
      showLabels: showLabels,
      viewHeightDeg: viewHeightDeg,
      occupiedLabels: occupiedLabels,
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
        oldDelegate.showLabels != showLabels ||
        oldDelegate.centerAltitudeDeg != centerAltitudeDeg ||
        oldDelegate.centerAzimuthDeg != centerAzimuthDeg ||
        oldDelegate.viewHeightDeg != viewHeightDeg ||
        oldDelegate.sunAltitudeDeg != sunAltitudeDeg ||
        oldDelegate.sunAzimuthDeg != sunAzimuthDeg ||
        oldDelegate.milkyWay != milkyWay ||
        oldDelegate.showMilkyWay != showMilkyWay ||
        oldDelegate.observationSiteHorizonProfile.points !=
            observationSiteHorizonProfile.points ||
        oldDelegate.observationSiteHorizonProfile.blockedRanges !=
            observationSiteHorizonProfile.blockedRanges ||
        oldDelegate.showObservationSiteHorizon != showObservationSiteHorizon;
  }
}
