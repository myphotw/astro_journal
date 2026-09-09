enum ExposureCapabilityType { discrete, range }

sealed class EquipmentExposureCapability {
  const EquipmentExposureCapability();

  ExposureCapabilityType get type;
  Map<String, Object?> toJson();

  factory EquipmentExposureCapability.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'discrete' => DiscreteExposureCapability(
        valuesSeconds: _numberList(json['values_seconds']),
      ),
      'range' => RangeExposureCapability(
        minSeconds: _number(json, 'min_seconds'),
        maxSeconds: _number(json, 'max_seconds'),
        stepSeconds: _number(json, 'step_seconds'),
      ),
      _ => throw const FormatException('Unknown exposure capability type.'),
    };
  }
}

class DiscreteExposureCapability extends EquipmentExposureCapability {
  const DiscreteExposureCapability({required this.valuesSeconds});

  final List<double> valuesSeconds;

  @override
  ExposureCapabilityType get type => ExposureCapabilityType.discrete;

  @override
  Map<String, Object?> toJson() => {
    'type': 'discrete',
    'values_seconds': valuesSeconds,
  };
}

class RangeExposureCapability extends EquipmentExposureCapability {
  const RangeExposureCapability({
    required this.minSeconds,
    required this.maxSeconds,
    required this.stepSeconds,
  });

  final double minSeconds;
  final double maxSeconds;
  final double stepSeconds;

  @override
  ExposureCapabilityType get type => ExposureCapabilityType.range;

  @override
  Map<String, Object?> toJson() => {
    'type': 'range',
    'min_seconds': minSeconds,
    'max_seconds': maxSeconds,
    'step_seconds': stepSeconds,
  };
}

List<double> _numberList(Object? raw) {
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('values_seconds must be a non-empty array.');
  }
  return raw
      .map((value) {
        if (value is! num) {
          throw const FormatException('values_seconds must contain numbers.');
        }
        return value.toDouble();
      })
      .toList(growable: false);
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key must be a number.');
  return value.toDouble();
}
