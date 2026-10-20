import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'celestial_position_service.dart';

@immutable
class SkyMapMilkyWayModel {
  const SkyMapMilkyWayModel({
    required this.longitudeCount,
    required this.latitudeCount,
    required this.image,
    required this.equatorialCoordinates,
    required this.textureCoordinates,
  });

  final int longitudeCount;
  final int latitudeCount;
  final ui.Image image;
  final List<EquatorialCoordinates> equatorialCoordinates;
  final List<ui.Offset> textureCoordinates;

  bool get isEmpty => equatorialCoordinates.isEmpty;
}

@immutable
class SkyMapMilkyWayHorizontalMesh {
  const SkyMapMilkyWayHorizontalMesh({
    required this.longitudeCount,
    required this.latitudeCount,
    required this.coordinates,
    required this.textureCoordinates,
    required this.image,
  });

  const SkyMapMilkyWayHorizontalMesh.empty()
    : longitudeCount = 0,
      latitudeCount = 0,
      coordinates = const [],
      textureCoordinates = const [],
      image = null;

  final int longitudeCount;
  final int latitudeCount;
  final List<AltAz> coordinates;
  final List<ui.Offset> textureCoordinates;
  final ui.Image? image;

  bool get isEmpty => coordinates.isEmpty || image == null;
}

/// Axel Mellinger의 가시광 전천 파노라마를 성도 좌표로 변환한다.
///
/// 파생 자산과 재배포 조건은 `Docs/SKY_MAP_MILKY_WAY_DATA.md`에 기록한다.
/// 텍스처는 Stellarium과 동일한 J2000 equirectangular 방향을 사용하며,
/// 정적 RA/Dec 메시를 한 번 만든 뒤 시각·관측지 변경 시 Alt/Az만 갱신한다.
class SkyMapMilkyWayService {
  const SkyMapMilkyWayService();

  static const assetPath =
      'assets/sky_map/mellinger_stellarium_visible_1024.png';
  static const double meshStepDeg = 3;

  static SkyMapMilkyWayModel? _cachedModel;
  static Future<SkyMapMilkyWayModel>? _loadingModel;

  Future<SkyMapMilkyWayModel> load({AssetBundle? bundle}) async {
    if (bundle != null) return _load(bundle);
    final cached = _cachedModel;
    if (cached != null) return cached;

    final loading = _loadingModel ??= _load(rootBundle);
    try {
      final loaded = await loading;
      _cachedModel = loaded;
      return loaded;
    } finally {
      if (identical(_loadingModel, loading)) _loadingModel = null;
    }
  }

  Future<SkyMapMilkyWayModel> _load(AssetBundle bundle) async {
    final bytes = await bundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;

    final longitudeCount = (360 / meshStepDeg).round() + 1;
    final latitudeCount = (180 / meshStepDeg).round() + 1;
    final pointCount = longitudeCount * latitudeCount;
    final equatorial = List<EquatorialCoordinates>.generate(pointCount, (
      index,
    ) {
      final row = index ~/ longitudeCount;
      final column = index % longitudeCount;
      final textureU = column / (longitudeCount - 1);
      final textureV = row / (latitudeCount - 1);
      return EquatorialCoordinates(
        raHours: _normalizeDegrees(90 - textureU * 360) / 15,
        decDeg: 90 - textureV * 180,
      );
    }, growable: false);
    final textureCoordinates = List<ui.Offset>.generate(pointCount, (index) {
      final row = index ~/ longitudeCount;
      final column = index % longitudeCount;
      return ui.Offset(
        column / (longitudeCount - 1) * image.width,
        row / (latitudeCount - 1) * image.height,
      );
    }, growable: false);

    return SkyMapMilkyWayModel(
      longitudeCount: longitudeCount,
      latitudeCount: latitudeCount,
      image: image,
      equatorialCoordinates: equatorial,
      textureCoordinates: textureCoordinates,
    );
  }

  SkyMapMilkyWayHorizontalMesh toHorizontal({
    required SkyMapMilkyWayModel model,
    required DateTime time,
    required double latitudeDeg,
    required double longitudeDeg,
  }) {
    if (model.isEmpty) return const SkyMapMilkyWayHorizontalMesh.empty();
    final coordinates = model.equatorialCoordinates
        .map(
          (equatorial) => CelestialPositionService.computeAltAz(
            raHours: equatorial.raHours,
            decDeg: equatorial.decDeg,
            latDeg: latitudeDeg,
            lonDeg: longitudeDeg,
            time: time,
          ),
        )
        .toList(growable: false);
    return SkyMapMilkyWayHorizontalMesh(
      longitudeCount: model.longitudeCount,
      latitudeCount: model.latitudeCount,
      coordinates: coordinates,
      textureCoordinates: model.textureCoordinates,
      image: model.image,
    );
  }

  /// Stellarium의 전천 텍스처 방향을 Flutter 이미지 좌표로 변환한다.
  /// RA 90°가 좌우 이음새이고 북극이 이미지 위쪽이다.
  @visibleForTesting
  static ui.Offset textureCoordinateForEquatorial({
    required double raDeg,
    required double decDeg,
    required double width,
    required double height,
  }) {
    final u = _normalizeDegrees(90 - raDeg) / 360;
    final v = (90 - decDeg.clamp(-90, 90)) / 180;
    return ui.Offset(u * width, v * height);
  }

  /// IAU Galactic II 단위벡터를 J2000 equatorial 좌표로 변환한다.
  @visibleForTesting
  static EquatorialCoordinates galacticToEquatorial({
    required double longitudeDeg,
    required double latitudeDeg,
  }) {
    final longitude = longitudeDeg * math.pi / 180;
    final latitude = latitudeDeg * math.pi / 180;
    final cosLatitude = math.cos(latitude);
    final galacticX = cosLatitude * math.cos(longitude);
    final galacticY = cosLatitude * math.sin(longitude);
    final galacticZ = math.sin(latitude);

    final equatorialX =
        -0.0548755604 * galacticX +
        0.4941094279 * galacticY -
        0.8676661490 * galacticZ;
    final equatorialY =
        -0.8734370902 * galacticX -
        0.4448296300 * galacticY -
        0.1980763734 * galacticZ;
    final equatorialZ =
        -0.4838350155 * galacticX +
        0.7469822445 * galacticY +
        0.4559837762 * galacticZ;

    final rightAscension = _normalizeDegrees(
      math.atan2(equatorialY, equatorialX) * 180 / math.pi,
    );
    final declination = math.asin(equatorialZ.clamp(-1.0, 1.0)) * 180 / math.pi;
    return EquatorialCoordinates(
      raHours: rightAscension / 15,
      decDeg: declination,
    );
  }

  static double _normalizeDegrees(double degrees) {
    final normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
