import '../../../data/models/equipment.dart';
import '../../../data/models/exif_info.dart';
import '../../../data/models/shooting_record.dart';

class GalleryEquipmentSelection {
  const GalleryEquipmentSelection({
    required this.equipmentId,
    required this.displayName,
    required this.preservedName,
    this.wasExplicitlyChanged = false,
  });

  factory GalleryEquipmentSelection.fromExif(ExifInfo? exif) {
    return GalleryEquipmentSelection(
      equipmentId: exif?.equipmentId,
      displayName: galleryEquipmentDisplayName(exif),
      preservedName: galleryEquipmentDisplayName(exif),
    );
  }

  final String? equipmentId;
  final String displayName;
  final String preservedName;
  final bool wasExplicitlyChanged;

  GalleryEquipmentSelection select(Equipment equipment) {
    return GalleryEquipmentSelection(
      equipmentId: equipment.id,
      displayName: equipment.name,
      preservedName: preservedName,
      wasExplicitlyChanged: true,
    );
  }

  GalleryEquipmentSelection unlink() {
    return GalleryEquipmentSelection(
      equipmentId: null,
      displayName: preservedName,
      preservedName: preservedName,
      wasExplicitlyChanged: true,
    );
  }
}

String galleryEquipmentDisplayName(ExifInfo? exif) {
  final current = exif?.equipment.trim() ?? '';
  if (current.isNotEmpty) return current;
  return exif?.equipmentNameSnapshot?.trim() ?? '';
}

ShootingRecord resolveGalleryEquipmentName(
  ShootingRecord record,
  Map<String, Equipment> equipmentById,
) {
  final exif = record.exif;
  if (exif == null) return record;
  final equipmentId = exif.equipmentId;
  final equipment = equipmentId == null ? null : equipmentById[equipmentId];
  final resolvedName = equipment?.name.trim().isNotEmpty == true
      ? equipment!.name.trim()
      : galleryEquipmentDisplayName(exif);
  if (resolvedName == exif.equipment &&
      (equipment == null ||
          (exif.equipmentIsActive == equipment.isActive &&
              exif.equipmentDeleted == false))) {
    return record;
  }
  return record.copyWith(
    exif: exif.copyWith(
      equipment: resolvedName,
      equipmentIsActive: equipment?.isActive,
      clearEquipmentIsActive: equipment == null,
      equipmentDeleted: equipment == null ? exif.equipmentDeleted : false,
    ),
  );
}
