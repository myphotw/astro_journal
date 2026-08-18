/// Parsed current-weather response from OpenWeatherMap.
class WeatherData {
  const WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.windDegree,
    required this.pressure,
    required this.cloudCoverage,
    required this.visibility,
    required this.sunrise,
    required this.sunset,
    required this.description,
    required this.cityName,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>? ?? {};
    final clouds = json['clouds'] as Map<String, dynamic>? ?? {};
    final sys = json['sys'] as Map<String, dynamic>? ?? {};
    final weatherList = json['weather'] as List<dynamic>?;
    final weather = weatherList?.isNotEmpty == true
        ? weatherList!.first as Map<String, dynamic>
        : null;

    return WeatherData(
      temperature: (main['temp'] as num).toDouble(),
      feelsLike: (main['feels_like'] as num).toDouble(),
      humidity: (main['humidity'] as num).toInt(),
      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0.0,
      windDegree: (wind['deg'] as num?)?.toInt() ?? 0,
      pressure: (main['pressure'] as num).toInt(),
      cloudCoverage: (clouds['all'] as num?)?.toInt() ?? 0,
      visibility: (json['visibility'] as num?)?.toInt() ?? 0,
      sunrise: DateTime.fromMillisecondsSinceEpoch(
        ((sys['sunrise'] as num?) ?? 0).toInt() * 1000,
      ),
      sunset: DateTime.fromMillisecondsSinceEpoch(
        ((sys['sunset'] as num?) ?? 0).toInt() * 1000,
      ),
      description: weather?['description'] as String? ?? '',
      cityName: json['name'] as String? ?? '',
    );
  }

  factory WeatherData.fromCacheJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] as num).toDouble(),
      feelsLike: (json['feelsLike'] as num).toDouble(),
      humidity: (json['humidity'] as num).toInt(),
      windSpeed: (json['windSpeed'] as num).toDouble(),
      windDegree: (json['windDegree'] as num).toInt(),
      pressure: (json['pressure'] as num).toInt(),
      cloudCoverage: (json['cloudCoverage'] as num).toInt(),
      visibility: (json['visibility'] as num).toInt(),
      sunrise: DateTime.parse(json['sunrise'] as String),
      sunset: DateTime.parse(json['sunset'] as String),
      description: json['description'] as String? ?? '',
      cityName: json['cityName'] as String? ?? '',
    );
  }

  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final int windDegree;
  final int pressure;
  final int cloudCoverage;

  /// Visibility in metres.
  final int visibility;
  final DateTime sunrise;
  final DateTime sunset;
  final String description;
  final String cityName;

  /// Cardinal direction label derived from [windDegree].
  String get windDirectionLabel {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((windDegree + 22.5) / 45).floor() % 8];
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'feelsLike': feelsLike,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'windDegree': windDegree,
      'pressure': pressure,
      'cloudCoverage': cloudCoverage,
      'visibility': visibility,
      'sunrise': sunrise.toIso8601String(),
      'sunset': sunset.toIso8601String(),
      'description': description,
      'cityName': cityName,
    };
  }
}
