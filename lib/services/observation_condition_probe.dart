import 'package:flutter/foundation.dart';

import '../data/models/observation_condition.dart';
import 'app_logger.dart';
import 'observation_condition_service.dart';

/// Debug-only probe that logs [ObservationCondition] without UI changes.
class ObservationConditionProbe {
  ObservationConditionProbe._();

  static const _tag = 'OBSERVATION';

  /// Fallback when GPS is unavailable (README 홍천).
  static const _fallbackLat = 37.6970;
  static const _fallbackLng = 127.8750;

  static Future<void> run(ObservationConditionService service) async {
    if (!kDebugMode) return;

    try {
      var condition = await _tryCurrent(service);
      condition ??= await service.getConditionAt(_fallbackLat, _fallbackLng);
      _logCondition(condition, usedFallback: condition.latitude == _fallbackLat);
    } catch (error, stack) {
      AppLogger.error(_tag, error, stack);
    }
  }

  static Future<ObservationCondition?> _tryCurrent(
    ObservationConditionService service,
  ) async {
    try {
      return await service.getCurrentCondition();
    } catch (error) {
      AppLogger.info(_tag, 'GPS unavailable, using fallback coordinates: $error');
      return null;
    }
  }

  static void _logCondition(
    ObservationCondition condition, {
    required bool usedFallback,
  }) {
    final prefix = usedFallback ? 'fallback ' : '';
    AppLogger.info(_tag, '${prefix}lat=${condition.latitude} lng=${condition.longitude}');
    AppLogger.info(_tag, 'Brightness : ${condition.brightness}');
    AppLogger.info(
      _tag,
      'ObservationScore : ${condition.observationScore?.round()}',
    );
    AppLogger.info(_tag, 'Row        : ${condition.row}');
    AppLogger.info(_tag, 'Col        : ${condition.col}');
    AppLogger.info(_tag, 'SQM        : ${condition.sqm}');
    AppLogger.info(_tag, 'Bortle     : ${condition.bortle}');
  }
}
