import '../../data/models/equipment_capture_capability.dart';
import '../../data/models/equipment_exposure_capability.dart';

enum EquipmentCapturePreset { seestarS30Pro, draco }

extension EquipmentCapturePresetLabel on EquipmentCapturePreset {
  String get label => switch (this) {
    EquipmentCapturePreset.seestarS30Pro => 'Seestar S30 Pro',
    EquipmentCapturePreset.draco => 'Draco',
  };
}

abstract final class EquipmentCapturePresets {
  static EquipmentCaptureCapability build(EquipmentCapturePreset preset) {
    return switch (preset) {
      EquipmentCapturePreset.seestarS30Pro => _seestarS30Pro,
      EquipmentCapturePreset.draco => _draco,
    };
  }

  /// These values are editable starting points supplied by the user. The
  /// backend does not currently own this extended capability contract.
  static const _seestarExposure = DiscreteExposureCapability(
    valuesSeconds: [2, 5, 10, 20, 30, 60],
  );

  static const _seestarS30Pro = EquipmentCaptureCapability(
    modes: [
      EquipmentCaptureModeCapability(
        id: EquipmentCaptureModeCapability.altAzId,
        type: EquipmentCaptureModeType.altAz,
        label: 'AZ',
        exposureCapability: _seestarExposure,
      ),
      EquipmentCaptureModeCapability(
        id: EquipmentCaptureModeCapability.equatorialId,
        type: EquipmentCaptureModeType.equatorial,
        label: 'EQ',
        exposureCapability: _seestarExposure,
      ),
    ],
    filters: [
      EquipmentFilterCapability(
        id: 'filter_off',
        type: EquipmentFilterType.off,
        name: '필터 끄기',
      ),
      EquipmentFilterCapability(
        id: 'dual_band',
        type: EquipmentFilterType.dualBand,
        name: '듀얼밴드',
      ),
    ],
  );

  static const _dracoExposure = DiscreteExposureCapability(
    valuesSeconds: [30, 45, 60, 90, 120, 180, 240, 300],
  );

  static const _draco = EquipmentCaptureCapability(
    modes: [
      EquipmentCaptureModeCapability(
        id: EquipmentCaptureModeCapability.altAzDerotatedId,
        type: EquipmentCaptureModeType.altAzDerotated,
        label: 'AZ 센서 회전 보정',
        exposureCapability: _dracoExposure,
      ),
      EquipmentCaptureModeCapability(
        id: EquipmentCaptureModeCapability.equatorialId,
        type: EquipmentCaptureModeType.equatorial,
        label: 'EQ',
        exposureCapability: _dracoExposure,
      ),
    ],
    gainCapability: DiscreteGainCapability(
      values: [
        0,
        2,
        5,
        10,
        20,
        30,
        40,
        50,
        60,
        70,
        80,
        90,
        100,
        110,
        120,
        130,
        140,
        150,
        160,
        170,
        180,
        190,
        200,
        210,
        220,
        230,
        240,
      ],
    ),
    filters: [
      EquipmentFilterCapability(
        id: 'filter_off',
        type: EquipmentFilterType.off,
        name: '필터 끄기',
      ),
      EquipmentFilterCapability(
        id: 'dual_band_ho',
        type: EquipmentFilterType.dualBand,
        name: 'HO 듀얼밴드',
      ),
      EquipmentFilterCapability(
        id: 'dual_band_so',
        type: EquipmentFilterType.dualBand,
        name: 'SO 듀얼밴드',
      ),
      EquipmentFilterCapability(
        id: 'sho',
        type: EquipmentFilterType.narrowBand,
        name: 'SHO',
      ),
    ],
    channelCombinations: [
      EquipmentChannelCombinationCapability(
        id: 'sho_so_ho',
        name: 'SHO SO:HO',
        primaryLabel: 'SO',
        secondaryLabel: 'HO',
        ratioAdjustable: true,
        minPrimaryPercent: 0,
        maxPrimaryPercent: 100,
        stepPercent: 1,
      ),
    ],
  );
}
