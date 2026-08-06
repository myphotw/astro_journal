import '../../core/constants/database_constants.dart';
import '../../core/constants/equipment_kind.dart';
import '../../core/constants/equipment_purpose.dart';
import '../../core/utils/fov_input_parser.dart';
import 'eyepiece.dart';

class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.kind,
    required this.purpose,
    this.isActive = true,
    this.focalLengthMm,
    this.fovWidthDegrees,
    this.fovHeightDegrees,
    this.apertureMm,
    this.sortOrder = 0,
    this.eyepieces = const [],
  });

  final String id;
  final String name;
  final EquipmentKind kind;
  final EquipmentPurpose purpose;
  final bool isActive;

  /// 촬영·안시 공통 초점거리 (mm). 촬영 장비는 FOV와 함께 사용.
  final double? focalLengthMm;

  /// 촬영 장비 시야 가로·세로 (°).
  final double? fovWidthDegrees;
  final double? fovHeightDegrees;

  /// 안시 장비 구경 (mm).
  final double? apertureMm;

  final int sortOrder;
  final List<Eyepiece> eyepieces;

  bool get isImaging => purpose == EquipmentPurpose.imaging;
  bool get isVisual => purpose == EquipmentPurpose.visual;

  bool get hasFov =>
      fovWidthDegrees != null &&
      fovHeightDegrees != null &&
      fovWidthDegrees! > 0 &&
      fovHeightDegrees! > 0;

  String get fovLabel {
    if (!hasFov) return '-';
    return FovInputParser.formatPair(fovWidthDegrees!, fovHeightDegrees!);
  }

  /// F값 = 초점거리 ÷ 구경 (안시 장비).
  double? get fRatio {
    if (apertureMm == null ||
        focalLengthMm == null ||
        apertureMm! <= 0) {
      return null;
    }
    return focalLengthMm! / apertureMm!;
  }

  Map<String, dynamic> toMap() {
    return {
      DatabaseConstants.colId: id,
      DatabaseConstants.colName: name,
      DatabaseConstants.colEquipmentKind: kind.name,
      DatabaseConstants.colEquipmentPurpose: purpose.name,
      DatabaseConstants.colIsActive: isActive ? 1 : 0,
      DatabaseConstants.colFocalLengthMm: focalLengthMm,
      DatabaseConstants.colFovWidthDegrees: fovWidthDegrees,
      DatabaseConstants.colFovHeightDegrees: fovHeightDegrees,
      DatabaseConstants.colFovDegrees: hasFov
          ? (fovWidthDegrees! > fovHeightDegrees!
              ? fovWidthDegrees
              : fovHeightDegrees)
          : null,
      DatabaseConstants.colApertureMm: apertureMm,
      DatabaseConstants.colSortOrder: sortOrder,
    };
  }

  factory Equipment.fromMap(
    Map<String, dynamic> map, {
    List<Eyepiece> eyepieces = const [],
  }) {
    final width =
        (map[DatabaseConstants.colFovWidthDegrees] as num?)?.toDouble();
    final height =
        (map[DatabaseConstants.colFovHeightDegrees] as num?)?.toDouble();
    final legacy =
        (map[DatabaseConstants.colFovDegrees] as num?)?.toDouble();

    final fovWidth = width ?? legacy;
    final fovHeight = height ?? legacy;

    return Equipment(
      id: map[DatabaseConstants.colId] as String,
      name: map[DatabaseConstants.colName] as String,
      kind: EquipmentKind.fromValue(
        map[DatabaseConstants.colEquipmentKind] as String,
      ),
      purpose: EquipmentPurpose.fromValue(
        map[DatabaseConstants.colEquipmentPurpose] as String,
      ),
      isActive: (map[DatabaseConstants.colIsActive] as int? ?? 1) == 1,
      focalLengthMm: (map[DatabaseConstants.colFocalLengthMm] as num?)
          ?.toDouble(),
      fovWidthDegrees: fovWidth,
      fovHeightDegrees: fovHeight,
      apertureMm: (map[DatabaseConstants.colApertureMm] as num?)?.toDouble(),
      sortOrder: map[DatabaseConstants.colSortOrder] as int? ?? 0,
      eyepieces: eyepieces,
    );
  }

  Equipment copyWith({
    String? id,
    String? name,
    EquipmentKind? kind,
    EquipmentPurpose? purpose,
    bool? isActive,
    double? focalLengthMm,
    double? fovWidthDegrees,
    double? fovHeightDegrees,
    double? apertureMm,
    int? sortOrder,
    List<Eyepiece>? eyepieces,
  }) {
    return Equipment(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      purpose: purpose ?? this.purpose,
      isActive: isActive ?? this.isActive,
      focalLengthMm: focalLengthMm ?? this.focalLengthMm,
      fovWidthDegrees: fovWidthDegrees ?? this.fovWidthDegrees,
      fovHeightDegrees: fovHeightDegrees ?? this.fovHeightDegrees,
      apertureMm: apertureMm ?? this.apertureMm,
      sortOrder: sortOrder ?? this.sortOrder,
      eyepieces: eyepieces ?? this.eyepieces,
    );
  }
}
