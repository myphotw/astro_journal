import 'equipment_exposure_capability.dart';

enum EquipmentCaptureModeType {
  altAz('AZ'),
  equatorial('EQ'),
  altAzDerotated('AZ 센서 회전 보정'),
  custom('사용자 정의');

  const EquipmentCaptureModeType(this.label);

  final String label;
}

class EquipmentCaptureModeCapability {
  const EquipmentCaptureModeCapability({
    required this.id,
    required this.type,
    required this.label,
    this.exposureCapability,
  });

  static const altAzId = 'alt_az';
  static const equatorialId = 'equatorial';
  static const altAzDerotatedId = 'alt_az_derotated';

  final String id;
  final EquipmentCaptureModeType type;
  final String label;
  final EquipmentExposureCapability? exposureCapability;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'label': label,
    'exposure_capability': exposureCapability?.toJson(),
  };

  factory EquipmentCaptureModeCapability.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    final type = EquipmentCaptureModeType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => throw const FormatException('Unknown capture mode type.'),
    );
    final exposure = json['exposure_capability'];
    return EquipmentCaptureModeCapability(
      id: _requiredString(json, 'id'),
      type: type,
      label: _requiredString(json, 'label'),
      exposureCapability: exposure is Map
          ? EquipmentExposureCapability.fromJson(
              Map<String, dynamic>.from(exposure),
            )
          : null,
    );
  }
}

enum GainCapabilityType { discrete, range }

sealed class EquipmentGainCapability {
  const EquipmentGainCapability();

  GainCapabilityType get type;
  Map<String, Object?> toJson();

  bool supports(double value);

  factory EquipmentGainCapability.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'discrete' => DiscreteGainCapability(
        values: _numberList(json['values'], allowZero: true),
      ),
      'range' => RangeGainCapability(
        min: _number(json, 'min'),
        max: _number(json, 'max'),
        step: _number(json, 'step'),
      ),
      _ => throw const FormatException('Unknown gain capability type.'),
    };
  }
}

class DiscreteGainCapability extends EquipmentGainCapability {
  const DiscreteGainCapability({required this.values});

  final List<double> values;

  @override
  GainCapabilityType get type => GainCapabilityType.discrete;

  @override
  Map<String, Object?> toJson() => {'type': type.name, 'values': values};

  @override
  bool supports(double value) => values.any((item) => _near(item, value));
}

class RangeGainCapability extends EquipmentGainCapability {
  const RangeGainCapability({
    required this.min,
    required this.max,
    required this.step,
  });

  final double min;
  final double max;
  final double step;

  @override
  GainCapabilityType get type => GainCapabilityType.range;

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'min': min,
    'max': max,
    'step': step,
  };

  @override
  bool supports(double value) {
    if (value < min || value > max || step <= 0) return false;
    return _near((value - min) / step, ((value - min) / step).roundToDouble());
  }
}

enum EquipmentFilterType {
  off('필터 끄기'),
  broadband('광대역'),
  dualBand('듀얼밴드'),
  narrowBand('협대역'),
  custom('사용자 정의');

  const EquipmentFilterType(this.label);

  final String label;
}

class EquipmentFilterCapability {
  const EquipmentFilterCapability({
    required this.id,
    required this.type,
    required this.name,
  });

  final String id;
  final EquipmentFilterType type;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'type': type.name, 'name': name};

  factory EquipmentFilterCapability.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    return EquipmentFilterCapability(
      id: _requiredString(json, 'id'),
      type: EquipmentFilterType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () =>
            throw const FormatException('Unknown equipment filter type.'),
      ),
      name: _requiredString(json, 'name'),
    );
  }
}

class EquipmentChannelCombinationCapability {
  const EquipmentChannelCombinationCapability({
    required this.id,
    required this.name,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.ratioAdjustable = false,
    this.minPrimaryPercent = 0,
    this.maxPrimaryPercent = 100,
    this.stepPercent = 1,
  });

  final String id;
  final String name;
  final String primaryLabel;
  final String secondaryLabel;
  final bool ratioAdjustable;
  final int minPrimaryPercent;
  final int maxPrimaryPercent;
  final int stepPercent;

  bool supportsPrimaryPercent(int value) {
    if (!ratioAdjustable || stepPercent <= 0) return false;
    if (value < minPrimaryPercent || value > maxPrimaryPercent) return false;
    return (value - minPrimaryPercent) % stepPercent == 0;
  }

  bool isValidRatio({
    required int primaryPercent,
    required int secondaryPercent,
  }) {
    return primaryPercent + secondaryPercent == 100 &&
        supportsPrimaryPercent(primaryPercent);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'primary_label': primaryLabel,
    'secondary_label': secondaryLabel,
    'ratio_adjustable': ratioAdjustable,
    'min_primary_percent': minPrimaryPercent,
    'max_primary_percent': maxPrimaryPercent,
    'step_percent': stepPercent,
  };

  factory EquipmentChannelCombinationCapability.fromJson(
    Map<String, dynamic> json,
  ) => EquipmentChannelCombinationCapability(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    primaryLabel: _requiredString(json, 'primary_label'),
    secondaryLabel: _requiredString(json, 'secondary_label'),
    ratioAdjustable: json['ratio_adjustable'] == true,
    minPrimaryPercent: _requiredInt(json, 'min_primary_percent'),
    maxPrimaryPercent: _requiredInt(json, 'max_primary_percent'),
    stepPercent: _requiredInt(json, 'step_percent'),
  );
}

class EquipmentCaptureCapability {
  const EquipmentCaptureCapability({
    this.modes = const [],
    this.gainCapability,
    this.filters = const [],
    this.channelCombinations = const [],
  });

  final List<EquipmentCaptureModeCapability> modes;
  final EquipmentGainCapability? gainCapability;
  final List<EquipmentFilterCapability> filters;
  final List<EquipmentChannelCombinationCapability> channelCombinations;

  bool get isEmpty =>
      modes.isEmpty &&
      gainCapability == null &&
      filters.isEmpty &&
      channelCombinations.isEmpty;

  EquipmentCaptureCapability copyWith({
    List<EquipmentCaptureModeCapability>? modes,
    EquipmentGainCapability? gainCapability,
    bool clearGainCapability = false,
    List<EquipmentFilterCapability>? filters,
    List<EquipmentChannelCombinationCapability>? channelCombinations,
  }) => EquipmentCaptureCapability(
    modes: modes ?? this.modes,
    gainCapability: clearGainCapability
        ? null
        : (gainCapability ?? this.gainCapability),
    filters: filters ?? this.filters,
    channelCombinations: channelCombinations ?? this.channelCombinations,
  );

  EquipmentCaptureModeCapability? modeById(String id) {
    for (final mode in modes) {
      if (mode.id == id) return mode;
    }
    return null;
  }

  bool supportsExposure(String modeId, double seconds) {
    final capability = modeById(modeId)?.exposureCapability;
    if (capability == null || !seconds.isFinite || seconds <= 0) return false;
    return switch (capability) {
      DiscreteExposureCapability(:final valuesSeconds) => valuesSeconds.any(
        (value) => _near(value, seconds),
      ),
      RangeExposureCapability(
        :final minSeconds,
        :final maxSeconds,
        :final stepSeconds,
      ) =>
        seconds >= minSeconds &&
            seconds <= maxSeconds &&
            stepSeconds > 0 &&
            _near(
              (seconds - minSeconds) / stepSeconds,
              ((seconds - minSeconds) / stepSeconds).roundToDouble(),
            ),
      FreeInputExposureCapability(:final minSeconds, :final maxSeconds) =>
        seconds >= minSeconds && seconds <= maxSeconds,
    };
  }

  void validate() {
    final modeIds = <String>{};
    for (final mode in modes) {
      if (mode.id.trim().isEmpty || mode.label.trim().isEmpty) {
        throw ArgumentError('촬영 모드 이름은 비워 둘 수 없습니다.');
      }
      if (!modeIds.add(mode.id)) {
        throw ArgumentError('같은 촬영 모드를 중복 등록할 수 없습니다.');
      }
      _validateExposure(mode.exposureCapability);
    }

    switch (gainCapability) {
      case DiscreteGainCapability(:final values):
        if (values.isEmpty ||
            values.any((value) => !value.isFinite || value < 0)) {
          throw ArgumentError('Gain 선택값은 0 이상의 숫자여야 합니다.');
        }
      case RangeGainCapability(:final min, :final max, :final step):
        if (!min.isFinite ||
            !max.isFinite ||
            !step.isFinite ||
            min < 0 ||
            max < min ||
            step <= 0) {
          throw ArgumentError('Gain 범위가 올바르지 않습니다.');
        }
      case null:
        break;
    }

    final filterIds = <String>{};
    for (final filter in filters) {
      if (filter.id.trim().isEmpty || filter.name.trim().isEmpty) {
        throw ArgumentError('필터 이름은 비워 둘 수 없습니다.');
      }
      if (!filterIds.add(filter.id)) {
        throw ArgumentError('같은 필터를 중복 등록할 수 없습니다.');
      }
    }

    final combinationIds = <String>{};
    for (final combination in channelCombinations) {
      if (combination.id.trim().isEmpty ||
          combination.name.trim().isEmpty ||
          combination.primaryLabel.trim().isEmpty ||
          combination.secondaryLabel.trim().isEmpty) {
        throw ArgumentError('채널 조합 이름은 비워 둘 수 없습니다.');
      }
      if (!combinationIds.add(combination.id)) {
        throw ArgumentError('같은 채널 조합을 중복 등록할 수 없습니다.');
      }
      if (combination.ratioAdjustable &&
          (combination.minPrimaryPercent < 0 ||
              combination.maxPrimaryPercent > 100 ||
              combination.maxPrimaryPercent < combination.minPrimaryPercent ||
              combination.stepPercent <= 0)) {
        throw ArgumentError('채널 조합 비율 범위가 올바르지 않습니다.');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'modes': modes.map((item) => item.toJson()).toList(growable: false),
    'gain_capability': gainCapability?.toJson(),
    'filters': filters.map((item) => item.toJson()).toList(growable: false),
    'channel_combinations': channelCombinations
        .map((item) => item.toJson())
        .toList(growable: false),
  };

  factory EquipmentCaptureCapability.fromJson(Map<String, dynamic> json) {
    final gain = json['gain_capability'];
    final result = EquipmentCaptureCapability(
      modes: _mapList(json['modes'], EquipmentCaptureModeCapability.fromJson),
      gainCapability: gain is Map
          ? EquipmentGainCapability.fromJson(Map<String, dynamic>.from(gain))
          : null,
      filters: _mapList(json['filters'], EquipmentFilterCapability.fromJson),
      channelCombinations: _mapList(
        json['channel_combinations'],
        EquipmentChannelCombinationCapability.fromJson,
      ),
    );
    result.validate();
    return result;
  }
}

void _validateExposure(EquipmentExposureCapability? capability) {
  switch (capability) {
    case DiscreteExposureCapability(:final valuesSeconds):
      if (valuesSeconds.isEmpty ||
          valuesSeconds.any((value) => !value.isFinite || value <= 0)) {
        throw ArgumentError('노출시간 선택값은 0보다 커야 합니다.');
      }
    case RangeExposureCapability(
      :final minSeconds,
      :final maxSeconds,
      :final stepSeconds,
    ):
      if (!minSeconds.isFinite ||
          !maxSeconds.isFinite ||
          !stepSeconds.isFinite ||
          minSeconds <= 0 ||
          maxSeconds < minSeconds ||
          stepSeconds <= 0) {
        throw ArgumentError('노출시간 범위가 올바르지 않습니다.');
      }
    case FreeInputExposureCapability(:final minSeconds, :final maxSeconds):
      if (!minSeconds.isFinite ||
          !maxSeconds.isFinite ||
          minSeconds <= 0 ||
          maxSeconds < minSeconds) {
        throw ArgumentError('자유 입력 노출시간 범위가 올바르지 않습니다.');
      }
    case null:
      break;
  }
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw == null) return const [];
  if (raw is! List) throw const FormatException('Capability list is invalid.');
  return raw
      .map((item) {
        if (item is! Map) {
          throw const FormatException('Capability item is invalid.');
        }
        return parse(Map<String, dynamic>.from(item));
      })
      .toList(growable: false);
}

List<double> _numberList(Object? raw, {required bool allowZero}) {
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('Capability values must be a non-empty list.');
  }
  return raw
      .map((item) {
        if (item is! num) {
          throw const FormatException('Capability value is invalid.');
        }
        final value = item.toDouble();
        if (!value.isFinite || (allowZero ? value < 0 : value <= 0)) {
          throw const FormatException('Capability value is out of range.');
        }
        return value;
      })
      .toList(growable: false);
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key must be numeric.');
  return value.toDouble();
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num || value.toInt() != value) {
    throw FormatException('$key must be an integer.');
  }
  return value.toInt();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _near(double left, double right) => (left - right).abs() < 1e-9;
