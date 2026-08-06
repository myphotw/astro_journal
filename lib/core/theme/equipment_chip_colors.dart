import 'package:flutter/material.dart';

/// 장비 Chip 고정 색상 (Dark Theme · Material 3 톤).
class EquipmentChipColors {
  EquipmentChipColors._();

  /// 알려진 장비 ID/이름 키워드 → 색상.
  static const Map<String, Color> _knownColors = {
  };

  static const List<Color> _fallbackPalette = [
    Color(0xFF60A5FA), // blue
    Color(0xFF34D399), // green
    Color(0xFFA78BFA), // purple
    Color(0xFF38BDF8), // sky
    Color(0xFFF472B6), // pink
    Color(0xFFFBBF24), // amber
    Color(0xFF2DD4BF), // teal
    Color(0xFF818CF8), // indigo
  ];

  /// 안시(visual) Chip 기본 색.
  static const Color visualDefault = Color(0xFFA78BFA);

  static Color resolve({
    required String equipmentId,
    required String label,
    bool isVisual = false,
  }) {
    if (isVisual) {
      return _resolveKnown(equipmentId, label) ?? visualDefault;
    }

    final known = _resolveKnown(equipmentId, label);
    if (known != null) return known;

    final key = equipmentId.isNotEmpty ? equipmentId : label;
    final index = key.hashCode.abs() % _fallbackPalette.length;
    return _fallbackPalette[index];
  }

  static Color? _resolveKnown(String equipmentId, String label) {
    final idLower = equipmentId.toLowerCase();
    final labelLower = label.toLowerCase();

    if (_matchesS30(idLower, labelLower)) {
      return const Color(0xFF60A5FA);
    }
    if (_matchesS50(idLower, labelLower)) {
      return const Color(0xFF34D399);
    }
    if (_matchesVisual(idLower, labelLower)) {
      return visualDefault;
    }

    for (final entry in _knownColors.entries) {
      if (idLower.contains(entry.key) || labelLower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static bool _matchesS30(String id, String label) =>
      id.contains('s30') || label.contains('s30');

  static bool _matchesS50(String id, String label) =>
      id.contains('s50') || label.contains('s50');

  static bool _matchesVisual(String id, String label) {
    if (label == '안시') return true;
    return id.contains('bcto') ||
        label.contains('bcto') ||
        label.contains('안시');
  }

  static Color background(Color accent, {bool onDarkBackground = false}) {
    if (onDarkBackground) return Colors.black.withAlpha(140);
    return accent.withAlpha(44);
  }

  static Color foreground(Color accent, {bool onDarkBackground = false}) {
    if (onDarkBackground) return Colors.white;
    return accent;
  }
}
