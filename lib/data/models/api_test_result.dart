/// Result from an API connection test.
class ApiTestResult {
  const ApiTestResult._({
    required this.success,
    required this.message,
    this.statusCode,
    this.responseTimeMs,
    this.data,
  });

  factory ApiTestResult.success({
    required int statusCode,
    required int responseTimeMs,
    required Map<String, dynamic> data,
    String message = '연결 성공',
  }) =>
      ApiTestResult._(
        success: true,
        message: message,
        statusCode: statusCode,
        responseTimeMs: responseTimeMs,
        data: data,
      );

  factory ApiTestResult.failure({
    required String message,
    int? statusCode,
    int? responseTimeMs,
  }) =>
      ApiTestResult._(
        success: false,
        message: message,
        statusCode: statusCode,
        responseTimeMs: responseTimeMs,
      );

  final bool success;
  final String message;
  final int? statusCode;
  final int? responseTimeMs;

  /// Parsed response body on success.
  final Map<String, dynamic>? data;
}
