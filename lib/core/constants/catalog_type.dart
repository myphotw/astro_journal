import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum CatalogType {  messier('messier', '메시에'),
  ngc('ngc', 'NGC'),
  sh2('sh2', 'Sh2'),
  ic('ic', 'IC'),
  caldwell('caldwell', 'Caldwell'),
  rcw('rcw', 'RCW'),
  vdb('vdb', 'vdB'),
  barnard('barnard', 'Barnard'),
  ldn('ldn', 'LDN'),
  lbn('lbn', 'LBN'),
  star('star', '별'),
  solar('solar', '태양계'),
  milky('milky', '은하수');

  const CatalogType(this.value, this.label);

  final String value;
  final String label;

  static CatalogType fromValue(String value) {
    return CatalogType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => CatalogType.ngc,
    );
  }

  static CatalogType? tryFromValue(String value) {
    for (final type in CatalogType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }

  /// 대표 카탈로그 우선순위 (낮을수록 우선).
  int get mergePriority {
    switch (this) {
      case CatalogType.messier:
        return 0;
      case CatalogType.ngc:
        return 1;
      case CatalogType.ic:
        return 2;
      case CatalogType.caldwell:
        return 3;
      case CatalogType.sh2:
        return 4;
      case CatalogType.rcw:
        return 5;
      case CatalogType.vdb:
        return 6;
      case CatalogType.barnard:
        return 7;
      case CatalogType.ldn:
        return 8;
      case CatalogType.lbn:
        return 9;
      case CatalogType.star:
        return 10;
      case CatalogType.solar:
      case CatalogType.milky:
        return 99;
    }
  }
}

extension CatalogTypeColors on CatalogType {
  Color get accentColor {
    switch (this) {
      case CatalogType.messier:
        return AppColors.messier;
      case CatalogType.ngc:
        return AppColors.ngc;
      case CatalogType.sh2:
        return AppColors.sh2;
      case CatalogType.ic:
        return AppColors.ic;
      case CatalogType.caldwell:
        return AppColors.caldwell;
      case CatalogType.rcw:
        return AppColors.rcw;
      case CatalogType.vdb:
        return AppColors.vdb;
      case CatalogType.barnard:
        return AppColors.barnard;
      case CatalogType.ldn:
        return AppColors.ldn;
      case CatalogType.lbn:
        return AppColors.lbn;
      case CatalogType.star:
        return AppColors.star;
      case CatalogType.solar:
        return AppColors.solar;
      case CatalogType.milky:
        return AppColors.milky;
    }
  }
}
