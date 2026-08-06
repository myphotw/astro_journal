/// 관리자 등록 장비 종류.
enum EquipmentKind {
  smartTelescope('스마트망원경'),
  refractor('굴절망원경'),
  reflector('반사망원경'),
  other('기타');

  const EquipmentKind(this.label);

  final String label;

  static EquipmentKind fromValue(String value) {
    return EquipmentKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => EquipmentKind.other,
    );
  }
}
