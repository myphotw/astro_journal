/// 장비 사용 목적.
enum EquipmentPurpose {
  imaging('촬영'),
  visual('안시');

  const EquipmentPurpose(this.label);

  final String label;

  static EquipmentPurpose fromValue(String value) {
    return EquipmentPurpose.values.firstWhere(
      (p) => p.name == value,
      orElse: () => EquipmentPurpose.imaging,
    );
  }
}
