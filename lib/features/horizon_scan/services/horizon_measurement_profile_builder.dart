import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../data/models/blocked_azimuth_range.dart';
import '../../../data/models/horizon_point.dart';
import '../models/horizon_measurement_result.dart';

class HorizonMeasurementProfileBuilder {
  const HorizonMeasurementProfileBuilder({this.outputStepDegrees = 10});

  final int outputStepDegrees;

  HorizonMeasurementResult build({
    required String observationSiteId,
    required List<HorizonBoundaryMeasurement> leftMeasurements,
    required List<HorizonBoundaryMeasurement> rightMeasurements,
    required List<HorizonBoundaryMeasurement> upperMeasurements,
    required List<HorizonBoundaryMeasurement> lowerMeasurements,
  }) {
    final hasLeft = leftMeasurements.isNotEmpty;
    final hasRight = rightMeasurements.isNotEmpty;
    if (hasLeft != hasRight) {
      throw ArgumentError('왼쪽과 오른쪽 경계는 모두 측정하거나 모두 건너뛰어야 합니다.');
    }

    final limited = hasLeft && hasRight;
    final start = limited ? _representativeAzimuth(leftMeasurements) : null;
    final end = limited ? _representativeAzimuth(rightMeasurements) : null;
    if (limited && start == end) {
      throw ArgumentError('왼쪽과 오른쪽 경계는 서로 다른 방향이어야 합니다.');
    }

    final lowerSamples = _canonicalSamples(lowerMeasurements);
    final upperSamples = _canonicalSamples(upperMeasurements);
    const uuid = Uuid();
    final points = <HorizonPoint>[
      for (var azimuth = 0; azimuth < 360; azimuth += outputStepDegrees)
        HorizonPoint(
          id: uuid.v4(),
          observationSiteId: observationSiteId,
          azimuth: azimuth.toDouble(),
          minAltitude: lowerSamples.isEmpty
              ? 0
              : limited
              ? _interpolateLimited(
                  azimuth.toDouble(),
                  lowerSamples,
                  start!,
                  end!,
                )
              : _interpolateCircular(azimuth.toDouble(), lowerSamples),
          maxAltitude: upperSamples.isEmpty
              ? 90
              : limited
              ? _interpolateLimited(
                  azimuth.toDouble(),
                  upperSamples,
                  start!,
                  end!,
                )
              : _interpolateCircular(azimuth.toDouble(), upperSamples),
          sortOrder: azimuth ~/ outputStepDegrees,
          source: HorizonDataSource.cameraScan,
        ),
    ];

    final blockedRanges = limited
        ? [
            BlockedAzimuthRange(
              id: uuid.v4(),
              observationSiteId: observationSiteId,
              startAzimuth: _normalize(end! + 1),
              endAzimuth: _normalize(start! - 1),
              reason: '시야 측정 도우미에서 관측 불가로 지정',
              source: HorizonDataSource.cameraScan,
            ),
          ]
        : const <BlockedAzimuthRange>[];

    return HorizonMeasurementResult(
      mode: limited
          ? HorizonMeasurementMode.limited
          : HorizonMeasurementMode.fullSky,
      points: points,
      blockedRanges: blockedRanges,
      leftMeasurements: List.unmodifiable(leftMeasurements),
      rightMeasurements: List.unmodifiable(rightMeasurements),
      upperMeasurements: List.unmodifiable(upperMeasurements),
      lowerMeasurements: List.unmodifiable(lowerMeasurements),
      startAzimuth: start,
      endAzimuth: end,
    );
  }

  List<({double azimuth, double altitude})> _canonicalSamples(
    List<HorizonBoundaryMeasurement> measurements,
  ) {
    final byAzimuth = <double, double>{};
    for (final measurement in measurements) {
      if (!measurement.azimuth.isFinite || !measurement.altitude.isFinite) {
        continue;
      }
      byAzimuth[_normalize(measurement.azimuth)] = measurement.altitude
          .clamp(0.0, 90.0)
          .toDouble();
    }
    return [
      for (final entry in byAzimuth.entries)
        (azimuth: entry.key, altitude: entry.value),
    ]..sort((a, b) => a.azimuth.compareTo(b.azimuth));
  }

  double _representativeAzimuth(
    List<HorizonBoundaryMeasurement> measurements,
  ) {
    var x = 0.0;
    var y = 0.0;
    for (final measurement in measurements) {
      final radians = _normalize(measurement.azimuth) * math.pi / 180;
      x += math.cos(radians);
      y += math.sin(radians);
    }
    if (x.abs() < 1e-9 && y.abs() < 1e-9) {
      return _normalize(measurements.first.azimuth).roundToDouble() % 360;
    }
    final degrees = math.atan2(y, x) * 180 / math.pi;
    return _normalize(degrees).roundToDouble() % 360;
  }

  double _interpolateLimited(
    double azimuth,
    List<({double azimuth, double altitude})> samples,
    double start,
    double end,
  ) {
    if (samples.length == 1) return samples.single.altitude;
    final span = _clockwiseDistance(start, end);
    final positioned = [
      for (final sample in samples)
        (
          distance: _clockwiseDistance(start, sample.azimuth),
          altitude: sample.altitude,
        ),
    ].where((sample) => sample.distance <= span + 1e-9).toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (positioned.isEmpty) {
      return _nearestAltitude(azimuth, samples);
    }
    if (positioned.length == 1) return positioned.single.altitude;

    final distance = _clockwiseDistance(
      start,
      azimuth,
    ).clamp(0.0, span).toDouble();
    if (distance <= positioned.first.distance) {
      return positioned.first.altitude;
    }
    if (distance >= positioned.last.distance) {
      return positioned.last.altitude;
    }
    for (var index = 0; index < positioned.length - 1; index++) {
      final left = positioned[index];
      final right = positioned[index + 1];
      if (distance < left.distance || distance > right.distance) continue;
      final ratio =
          (distance - left.distance) / (right.distance - left.distance);
      return left.altitude + (right.altitude - left.altitude) * ratio;
    }
    return positioned.last.altitude;
  }

  double _interpolateCircular(
    double azimuth,
    List<({double azimuth, double altitude})> samples,
  ) {
    if (samples.length == 1) return samples.single.altitude;
    final target = _normalize(azimuth);
    for (final sample in samples) {
      if ((sample.azimuth - target).abs() < 1e-9) return sample.altitude;
    }
    for (var index = 0; index < samples.length; index++) {
      final left = samples[index];
      final right = samples[(index + 1) % samples.length];
      final rightAzimuth = index == samples.length - 1
          ? right.azimuth + 360
          : right.azimuth;
      final adjustedTarget = index == samples.length - 1 && target < left.azimuth
          ? target + 360
          : target;
      if (adjustedTarget < left.azimuth || adjustedTarget > rightAzimuth) {
        continue;
      }
      final ratio = (adjustedTarget - left.azimuth) /
          (rightAzimuth - left.azimuth);
      return left.altitude + (right.altitude - left.altitude) * ratio;
    }
    return samples.first.altitude;
  }

  double _nearestAltitude(
    double azimuth,
    List<({double azimuth, double altitude})> samples,
  ) {
    final target = _normalize(azimuth);
    var nearest = samples.first;
    var nearestDistance = 360.0;
    for (final sample in samples) {
      final direct = (sample.azimuth - target).abs();
      final distance = math.min(direct, 360 - direct);
      if (distance < nearestDistance) {
        nearest = sample;
        nearestDistance = distance;
      }
    }
    return nearest.altitude;
  }

  double _clockwiseDistance(double from, double to) =>
      _normalize(_normalize(to) - _normalize(from));

  double _normalize(double value) {
    final normalized = value % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }
}
