import 'object_type.dart';

import 'surface_brightness_class.dart';



/// 안시 추천 가중치 및 점수 테이블 (기본 전제: 필터 없음).

abstract final class VisualObservationWeights {

  static const double surfaceBrightnessWeight = 0.40;

  static const double objectTypeWeight = 0.25;

  static const double magnitudeWeight = 0.10;

  static const double sizeFitWeight = 0.15;

  static const double telescopeWeight = 0.10;



  static const double recommendThreshold = 35;



  static const double minApertureVeryDimMm = 150;

  static const double minApertureExtremeDimMm = 200;

  static const double minApertureWideFieldMm = 150;



  /// 필터 없이 관측 시 발광·확산 성운 감점 배율.

  static const double noFilterNebulaPenalty = 0.60;



  /// M20 등 중간 난이도 성운 감점 배율.

  static const double noFilterModeratePenalty = 0.80;



  /// NGC2237 중앙 산개성단 유효 각경 (~15′).

  static const double centralClusterSizeDegrees = 0.25;



  static double surfaceBrightnessScore(SurfaceBrightnessClass brightness) {

    return switch (brightness) {

      SurfaceBrightnessClass.veryBright => 100,

      SurfaceBrightnessClass.bright => 85,

      SurfaceBrightnessClass.normal => 65,

      SurfaceBrightnessClass.dim => 40,

      SurfaceBrightnessClass.veryDim => 20,

      SurfaceBrightnessClass.extremeDim => 10,

    };

  }



  static double objectTypeScore(ObjectType type) {

    return switch (type) {

      ObjectType.globularCluster => 100,

      ObjectType.planetaryNebula => 95,

      ObjectType.openCluster => 85,

      ObjectType.doubleStar => 80,

      ObjectType.star => 75,

      ObjectType.galaxy => 60,

      ObjectType.galaxyGroup => 55,

      ObjectType.nebulaWithCluster => 50,

      ObjectType.complexNebula => 45,

      ObjectType.supernovaRemnant => 40,

      ObjectType.emissionNebula => 35,

      ObjectType.reflectionNebula => 30,

      ObjectType.starCloud => 25,

      ObjectType.milkyWay => 20,

      ObjectType.darkNebula => 15,

      ObjectType.planet => 90,

      ObjectType.moon => 85,

      ObjectType.dwarfPlanet => 30,

      ObjectType.other => 50,

    };

  }



  static double magnitudeScore(double? magnitude) {

    if (magnitude == null) return 55;

    if (magnitude <= 4) return 95;

    if (magnitude <= 6) return 85;

    if (magnitude <= 8) return 70;

    if (magnitude <= 10) return 55;

    if (magnitude <= 12) return 40;

    return 25;

  }



  /// 필터 없음 기준으로 감점 대상인 천체 종류.

  static bool isNoFilterPenalizedType(ObjectType type) {

    return switch (type) {

      ObjectType.emissionNebula ||

      ObjectType.reflectionNebula ||

      ObjectType.supernovaRemnant ||

      ObjectType.complexNebula ||

      ObjectType.nebulaWithCluster ||

      ObjectType.starCloud ||

      ObjectType.darkNebula ||

      ObjectType.milkyWay =>

        true,

      _ => false,

    };

  }

}

