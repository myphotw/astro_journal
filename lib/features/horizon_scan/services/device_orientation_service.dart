import 'dart:async';

import 'package:flutter/services.dart';

import '../models/horizon_scan_sample.dart';

abstract interface class DeviceOrientationService {
  Stream<OrientationSample> get samples;

  Future<void> start({double? latitude, double? longitude});

  Future<void> stop();
}

class NativeDeviceOrientationService implements DeviceOrientationService {
  NativeDeviceOrientationService({
    this.eventChannel = const EventChannel(
      'com.example.astro_journal/device_orientation',
    ),
  });

  final EventChannel eventChannel;
  final StreamController<OrientationSample> _samples =
      StreamController<OrientationSample>.broadcast(sync: true);
  StreamSubscription<dynamic>? _nativeSubscription;

  @override
  Stream<OrientationSample> get samples => _samples.stream;

  @override
  Future<void> start({double? latitude, double? longitude}) async {
    await stop();
    final arguments = <String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
    };
    _nativeSubscription = eventChannel
        .receiveBroadcastStream(arguments)
        .listen(
          (dynamic event) {
            try {
              _samples.add(_parse(event));
            } on Object catch (error, stackTrace) {
              _samples.addError(error, stackTrace);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _samples.addError(error, stackTrace);
          },
        );
  }

  @override
  Future<void> stop() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
  }

  OrientationSample _parse(dynamic event) {
    if (event is! Map) {
      throw const FormatException('방향 센서 응답 형식이 올바르지 않습니다.');
    }
    final azimuth = event['azimuth'];
    final pitch = event['pitch'];
    final roll = event['roll'];
    final timestamp = event['timestampNanos'];
    if (azimuth is! num || pitch is! num || roll is! num || timestamp is! num) {
      throw const FormatException('방향 센서 필수 값이 누락되었습니다.');
    }
    final accuracyName = event['accuracy'] as String?;
    return OrientationSample(
      sampledAt: DateTime.now(),
      sensorTimestampNanos: timestamp.toInt(),
      azimuth: azimuth.toDouble(),
      pitch: pitch.toDouble(),
      roll: roll.toDouble(),
      accuracy: HorizonSensorAccuracy.values.firstWhere(
        (value) => value.name == accuracyName,
        orElse: () => HorizonSensorAccuracy.unknown,
      ),
      trueNorthApplied: event['trueNorthApplied'] == true,
    );
  }
}
