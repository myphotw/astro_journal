enum TcBackendConnectionStatus {
  notConfigured,
  checking,
  connected,
  degraded,
  incompatible,
  unreachable,
}

class TcBackendHealth {
  const TcBackendHealth({
    this.status,
    this.database,
    this.storage,
    this.vision,
    this.weather,
    this.geocoding,
    this.version,
    this.time,
  });

  final String? status;
  final String? database;
  final String? storage;
  final String? vision;
  final String? weather;
  final String? geocoding;
  final String? version;
  final String? time;

  bool get isDegraded => status?.toLowerCase() == 'degraded';

  factory TcBackendHealth.fromJson(Map<String, dynamic> json) {
    return TcBackendHealth(
      status: _asString(json['status']),
      database: _asStatus(json['database']),
      storage: _asStatus(json['storage']),
      vision: _asStatus(json['vision']),
      weather: _asStatus(json['weather']),
      geocoding: _asStatus(json['geocoding']),
      version: _asString(json['version'] ?? json['service_version']),
      time: _asString(json['time'] ?? json['timestamp']),
    );
  }
}

class TcBackendCapabilities {
  const TcBackendCapabilities({
    this.apiVersion,
    this.serviceVersion,
    this.capabilities = const [],
    this.supportedServices = const [],
    this.supportsServiceName,
    this.supportsClientFileId,
  });

  final String? apiVersion;
  final String? serviceVersion;
  final List<String> capabilities;
  final List<String> supportedServices;
  final bool? supportsServiceName;
  final bool? supportsClientFileId;

  factory TcBackendCapabilities.fromJson(Map<String, dynamic> json) {
    final contract = _asMap(json['upload_contract']);
    return TcBackendCapabilities(
      apiVersion: _asString(json['api_version']),
      serviceVersion: _asString(json['service_version']),
      capabilities: _asStringList(json['capabilities']),
      supportedServices: _asStringList(json['supported_services']),
      supportsServiceName: _asBool(
        contract['supports_service_name'] ?? contract['supportsServiceName'],
      ),
      supportsClientFileId: _asBool(
        contract['supports_client_file_id'] ?? contract['supportsClientFileId'],
      ),
    );
  }
}

class TcBackendCheckResult {
  const TcBackendCheckResult({
    required this.status,
    this.health,
    this.capabilities,
    this.message,
  });

  final TcBackendConnectionStatus status;
  final TcBackendHealth? health;
  final TcBackendCapabilities? capabilities;
  final String? message;

  bool get isCompatible =>
      status == TcBackendConnectionStatus.connected ||
      status == TcBackendConnectionStatus.degraded;
}

String? _asString(Object? value) => value?.toString();

String? _asStatus(Object? value) {
  if (value is Map) return _asString(value['status'] ?? value['state']);
  return _asString(value);
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Object?>().map((item) => item.toString()).toList();
}

bool? _asBool(Object? value) => value is bool ? value : null;
