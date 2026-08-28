enum AstronomyEventType {
  meteorShower('meteor_shower'),
  solarEclipse('solar_eclipse'),
  lunarEclipse('lunar_eclipse'),
  planetViewing('planet_viewing'),
  conjunction('conjunction'),
  unknown('unknown');

  const AstronomyEventType(this.wireName);

  final String wireName;

  static AstronomyEventType fromWireName(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return AstronomyEventType.unknown;
  }
}

class AstronomyEvent {
  const AstronomyEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.tags,
    required this.priority,
    this.startAt,
    this.peakAt,
    this.endAt,
  });

  factory AstronomyEvent.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final rawType = _requiredString(json, 'type');
    final title = _requiredString(json, 'title');
    final rawTags = json['tags'];
    if (rawTags is! List || rawTags.any((tag) => tag is! String)) {
      throw const FormatException('events[].tags must be a JSON array.');
    }

    final rawPriority = json['priority'];
    if (rawPriority is! int) {
      throw const FormatException('events[].priority must be an integer.');
    }

    return AstronomyEvent(
      id: id,
      type: AstronomyEventType.fromWireName(rawType),
      title: title,
      startAt: _optionalUtcDateTime(json, 'start_at'),
      peakAt: _optionalUtcDateTime(json, 'peak_at'),
      endAt: _optionalUtcDateTime(json, 'end_at'),
      tags: List<String>.unmodifiable(
        rawTags
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty),
      ),
      priority: rawPriority.toInt(),
    );
  }

  final String id;
  final AstronomyEventType type;
  final String title;
  final DateTime? startAt;
  final DateTime? peakAt;
  final DateTime? endAt;
  final List<String> tags;
  final int priority;

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('events[].$key must be a non-empty string.');
    }
    return value.trim();
  }

  static DateTime? _optionalUtcDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('events[].$key must be an ISO-8601 string.');
    }
    return DateTime.parse(value).toUtc();
  }
}
