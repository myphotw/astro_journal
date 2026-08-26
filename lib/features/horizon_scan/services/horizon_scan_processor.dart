import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../../data/models/horizon_point.dart';
import '../models/horizon_scan_sample.dart';
import '../models/horizon_scan_session.dart';

/// Converts camera scan frames into a conservative circular horizon profile.
class HorizonScanProcessor {
  const HorizonScanProcessor({this.outputStepDegrees = 10});

  final int outputStepDegrees;

  List<HorizonPoint> process(HorizonScanSession session) {
    final verticalFov = session.cameraInformation?.verticalFov ?? 48.0;
    final estimates = <({double azimuth, double altitude})>[];

    for (final sample in session.samples) {
      final frame = sample.frame;
      if (frame == null ||
          frame.width < 4 ||
          frame.height < 4 ||
          frame.lumaBytes.length < frame.width * frame.height ||
          !sample.azimuth.isFinite ||
          !sample.pitch.isFinite ||
          sample.roll.abs() > 55) {
        continue;
      }
      final boundary = _detectBoundaryRow(frame);
      if (boundary == null) continue;
      final normalizedOffset = 0.5 - boundary / (frame.height - 1);
      final altitude = (sample.pitch + normalizedOffset * verticalFov)
          .clamp(0.0, 89.0)
          .toDouble();
      estimates.add((azimuth: _normalize(sample.azimuth), altitude: altitude));
    }

    if (estimates.isEmpty) return const [];
    final raw = <double>[];
    for (var azimuth = 0; azimuth < 360; azimuth += outputStepDegrees) {
      raw.add(_estimateAt(azimuth.toDouble(), estimates));
    }

    final smoothed = <double>[];
    for (var i = 0; i < raw.length; i++) {
      smoothed.add(
        _median([
          raw[(i - 1 + raw.length) % raw.length],
          raw[i],
          raw[(i + 1) % raw.length],
        ]),
      );
    }

    const uuid = Uuid();
    return [
      for (var i = 0; i < smoothed.length; i++)
        HorizonPoint(
          id: uuid.v4(),
          observationSiteId: session.observationSiteId,
          azimuth: (i * outputStepDegrees).toDouble(),
          minAltitude: smoothed[i].clamp(0.0, 89.0).toDouble(),
          sortOrder: i,
          source: HorizonDataSource.cameraScan,
        ),
    ];
  }

  double? _detectBoundaryRow(HorizonFrameReference frame) {
    final means = List<double>.filled(frame.height, 0);
    for (var y = 0; y < frame.height; y++) {
      var sum = 0;
      final offset = y * frame.width;
      for (var x = 0; x < frame.width; x++) {
        sum += frame.lumaBytes[offset + x];
      }
      means[y] = sum / frame.width;
    }

    final window = math.max(2, frame.height ~/ 24);
    final first = math.max(window, (frame.height * 0.08).round());
    final last = math.min(frame.height - window, (frame.height * 0.92).round());
    var bestRow = -1;
    var bestContrast = 0.0;
    for (var row = first; row < last; row++) {
      var above = 0.0;
      var below = 0.0;
      for (var i = 0; i < window; i++) {
        above += means[row - 1 - i];
        below += means[row + i];
      }
      final contrast = ((above - below) / window).abs();
      if (contrast > bestContrast) {
        bestContrast = contrast;
        bestRow = row;
      }
    }
    return bestRow < 0 || bestContrast < 4 ? null : bestRow.toDouble();
  }

  double _estimateAt(
    double azimuth,
    List<({double azimuth, double altitude})> estimates,
  ) {
    final nearby = estimates
        .where((item) => _angularDistance(item.azimuth, azimuth) <= 7.5)
        .map((item) => item.altitude)
        .toList();
    if (nearby.isNotEmpty) return _median(nearby);

    final sorted = [...estimates]
      ..sort(
        (a, b) => _angularDistance(
          a.azimuth,
          azimuth,
        ).compareTo(_angularDistance(b.azimuth, azimuth)),
      );
    final nearest = sorted.take(math.min(2, sorted.length)).toList();
    if (nearest.length == 1) return nearest.first.altitude;
    final d0 = math.max(0.1, _angularDistance(nearest[0].azimuth, azimuth));
    final d1 = math.max(0.1, _angularDistance(nearest[1].azimuth, azimuth));
    return (nearest[0].altitude / d0 + nearest[1].altitude / d1) /
        (1 / d0 + 1 / d1);
  }

  double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _angularDistance(double a, double b) {
    final difference = (_normalize(a) - _normalize(b)).abs();
    return math.min(difference, 360 - difference);
  }

  double _normalize(double degrees) => ((degrees % 360) + 360) % 360;
}
