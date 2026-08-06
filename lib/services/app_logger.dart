import 'package:flutter/foundation.dart';

/// Debug-only structured logger with category tagging.
class AppLogger {
  AppLogger._();

  static void request(
    String method,
    String url, {
    Map<String, String>? headers,
  }) {
    if (!kDebugMode) return;
    debugPrint('→ [$method] $url');
    if (headers != null) {
      final display = Map<String, String>.from(headers);
      if (display.containsKey('Authorization')) {
        display['Authorization'] = '***';
      }
      debugPrint('  Headers: $display');
    }
  }

  static void response(
    String url,
    int statusCode,
    String body, {
    required int elapsedMs,
  }) {
    if (!kDebugMode) return;
    final preview = body.length > 400 ? '${body.substring(0, 400)}…' : body;
    debugPrint('← [$statusCode] $url (${elapsedMs}ms)\n  $preview');
  }

  static void error(String tag, dynamic error, [StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('✗ [$tag] $error');
    if (stack != null) debugPrint('  $stack');
  }

  static void info(String tag, String message) {
    if (!kDebugMode) return;
    debugPrint('ℹ [$tag] $message');
  }

  /// 메타데이터 추출·병합 단계 로그 (debug 전용).
  static void metadata(String step, String message) {
    if (!kDebugMode) return;
    debugPrint('[METADATA] $step: $message');
  }

  /// GPS 관련 로그.
  static void gps(String message) {
    if (!kDebugMode) return;
    debugPrint('[GPS] $message');
  }

  /// Google Maps / Geocoding API 관련 로그.
  static void mapApi(String message) {
    if (!kDebugMode) return;
    debugPrint('[MAP] $message');
  }

  /// Astronomy API 관련 로그.
  static void astronomy(String message) {
    if (!kDebugMode) return;
    debugPrint('[ASTRONOMY] $message');
  }

  /// Weather API 관련 로그.
  static void weather(String message) {
    if (!kDebugMode) return;
    debugPrint('[WEATHER] $message');
  }
}
