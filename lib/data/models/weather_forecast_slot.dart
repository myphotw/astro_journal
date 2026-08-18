/// Parsed 3-hour forecast item from OpenWeatherMap `/forecast`.
class WeatherForecastSlot {
  const WeatherForecastSlot({
    required this.time,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.cloudCoverage,
    required this.visibility,
    required this.pop,
    required this.description,
    required this.icon,
    this.rainVolumeMm,
  });

  factory WeatherForecastSlot.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>? ?? {};
    final clouds = json['clouds'] as Map<String, dynamic>? ?? {};
    final rain = json['rain'] as Map<String, dynamic>?;
    final weatherList = json['weather'] as List<dynamic>?;
    final weather = weatherList?.isNotEmpty == true
        ? weatherList!.first as Map<String, dynamic>
        : null;

    double? rainVolumeMm;
    if (rain != null) {
      final volume = rain['3h'] ?? rain['1h'];
      if (volume != null) {
        rainVolumeMm = (volume as num).toDouble();
      }
    }

    return WeatherForecastSlot(
      time: DateTime.fromMillisecondsSinceEpoch(
        (json['dt'] as num).toInt() * 1000,
        isUtc: true,
      ).toLocal(),
      temperature: (main['temp'] as num).toDouble(),
      humidity: (main['humidity'] as num).toInt(),
      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0.0,
      cloudCoverage: (clouds['all'] as num?)?.toInt() ?? 0,
      visibility: (json['visibility'] as num?)?.toInt() ?? 10000,
      pop: ((json['pop'] as num?)?.toDouble() ?? 0) * 100,
      description: weather?['description'] as String? ?? '',
      icon: weather?['icon'] as String? ?? '',
      rainVolumeMm: rainVolumeMm,
    );
  }

  factory WeatherForecastSlot.fromCacheJson(Map<String, dynamic> json) {
    return WeatherForecastSlot(
      time: DateTime.parse(json['time'] as String),
      temperature: (json['temperature'] as num).toDouble(),
      humidity: (json['humidity'] as num).toInt(),
      windSpeed: (json['windSpeed'] as num).toDouble(),
      cloudCoverage: (json['cloudCoverage'] as num).toInt(),
      visibility: (json['visibility'] as num).toInt(),
      pop: (json['pop'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      rainVolumeMm: (json['rainVolumeMm'] as num?)?.toDouble(),
    );
  }

  final DateTime time;
  final double temperature;
  final int humidity;
  final double windSpeed;
  final int cloudCoverage;
  final int visibility;
  final double pop;
  final String description;
  final String icon;

  /// 3-hour (or 1-hour) precipitation volume in mm from OpenWeatherMap `rain`.
  final double? rainVolumeMm;

  bool get hasRainVolume => rainVolumeMm != null;

  String get weatherEmoji {
    if (icon.startsWith('01')) return '☀';
    if (icon.startsWith('02')) return '⛅';
    if (icon.startsWith('03') || icon.startsWith('04')) return '☁';
    if (icon.startsWith('09') || icon.startsWith('10')) return '🌧';
    if (icon.startsWith('11')) return '⛈';
    if (icon.startsWith('13')) return '❄';
    if (icon.startsWith('50')) return '🌫';
    return '🌤';
  }

  String get weatherLabel {
    if (description.isEmpty) return weatherEmoji;
    return '$weatherEmoji $description';
  }

  Map<String, dynamic> toJson() {
    return {
      'time': time.toIso8601String(),
      'temperature': temperature,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'cloudCoverage': cloudCoverage,
      'visibility': visibility,
      'pop': pop,
      'description': description,
      'icon': icon,
      if (rainVolumeMm != null) 'rainVolumeMm': rainVolumeMm,
    };
  }
}
