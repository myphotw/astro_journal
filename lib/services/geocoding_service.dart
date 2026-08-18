import 'package:uuid/uuid.dart';

import 'app_logger.dart';
import 'tc_backend_external_api_client.dart';
import 'tc_backend_settings_service.dart';

/// Geocoding and Places facade backed by TC-Backend.
///
/// The optional legacy API-key arguments remain source-compatible with V1
/// callers, but provider credentials are never read or sent by this service.
class GeocodingService {
  GeocodingService({TcBackendExternalApiClient? backendClient})
    : _backend =
          backendClient ??
          TcBackendExternalApiClient(
            settingsService: TcBackendSettingsService(),
          );

  final TcBackendExternalApiClient _backend;
  String? _placesSessionToken;

  Future<GeocodingResult?> getLocationInfo(
    double lat,
    double lng, [
    String? legacyApiKey,
  ]) async {
    try {
      final json = await _backend.getMap(
        '/api/common/geocoding/reverse',
        query: {
          'latitude': lat.toStringAsFixed(6),
          'longitude': lng.toStringAsFixed(6),
          'language': 'ko',
        },
      );
      final displayName = _string(json['display_name']);
      final province = _string(json['province']);
      final city = _string(json['city']);
      final district = _string(json['district']);
      final placeName = _string(json['place_name']);
      final address =
          displayName ??
          [province, city, district].whereType<String>().join(' ').trim();
      final locationName = placeName ?? district ?? city ?? province ?? address;
      if (locationName.isEmpty && address.isEmpty) return null;
      final regionName = approximateRegionName(
        level1: province,
        level2: city ?? district,
        locality: placeName,
      );
      return GeocodingResult(
        locationName: locationName.isNotEmpty ? locationName : address,
        address: address.isNotEmpty ? address : locationName,
        regionName: regionName.isNotEmpty ? regionName : locationName,
      );
    } on TcBackendExternalApiException catch (error) {
      AppLogger.info('GeocodingService', 'reverse failed: ${error.code.name}');
      return null;
    } catch (error, stackTrace) {
      AppLogger.error('GeocodingService', error, stackTrace);
      return null;
    }
  }

  Future<String?> getAddress(
    double lat,
    double lng, [
    String? legacyApiKey,
  ]) async => (await getLocationInfo(lat, lng))?.locationName;

  Future<GeocodeForwardResult?> geocodeAddress(
    String query, [
    String? legacyApiKey,
  ]) async {
    final results = await geocodeAddressAll(query);
    return results.isEmpty ? null : results.first;
  }

  Future<List<LocationSearchSuggestion>> autocompleteLocations(
    String query, [
    String? legacyApiKey,
  ]) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    _placesSessionToken ??= const Uuid().v4();
    try {
      final responses = await Future.wait([
        _backend.getMap(
          '/api/common/places/autocomplete',
          query: {
            'query': trimmed,
            'language': 'ko',
            'session_token': _placesSessionToken!,
          },
        ),
        _backend.getMap(
          '/api/common/geocoding/forward',
          query: {'query': trimmed, 'language': 'ko'},
        ),
      ]);
      final suggestions = <LocationSearchSuggestion>[];
      for (final raw in _items(responses[0])) {
        final placeId = _string(raw['place_id']);
        final mainText = _string(raw['main_text']);
        if (placeId == null || mainText == null) continue;
        suggestions.add(
          LocationSearchSuggestion(
            placeId: placeId,
            mainText: mainText,
            secondaryText: _string(raw['secondary_text']),
          ),
        );
      }
      suggestions.addAll(
        _items(responses[1]).map(_candidateSuggestion).whereType(),
      );
      return _mergeSuggestions(suggestions);
    } on TcBackendExternalApiException catch (error) {
      AppLogger.info(
        'GeocodingService',
        'autocomplete failed: ${error.code.name}',
      );
      return const [];
    } catch (error, stackTrace) {
      AppLogger.error('GeocodingService', error, stackTrace);
      return const [];
    }
  }

  Future<GeocodeForwardResult?> getPlaceDetails(
    String placeId, [
    String? legacyApiKey,
  ]) async {
    if (placeId.trim().isEmpty) return null;
    final sessionToken = _placesSessionToken;
    try {
      final json = await _backend.getMap(
        '/api/common/places/details',
        query: {
          'place_id': placeId.trim(),
          'language': 'ko',
          'session_token': ?sessionToken,
        },
      );
      return _candidate(json);
    } on TcBackendExternalApiException catch (error) {
      AppLogger.info('GeocodingService', 'details failed: ${error.code.name}');
      return null;
    } catch (error, stackTrace) {
      AppLogger.error('GeocodingService', error, stackTrace);
      return null;
    } finally {
      _placesSessionToken = null;
    }
  }

  Future<List<GeocodeForwardResult>> searchLocationsAll(
    String query, [
    String? legacyApiKey,
  ]) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final responses = await Future.wait([
        _backend.getMap(
          '/api/common/geocoding/forward',
          query: {'query': trimmed, 'language': 'ko'},
        ),
        _backend.getMap(
          '/api/common/places/search',
          query: {'query': trimmed, 'language': 'ko'},
        ),
      ]);
      return _mergeForwardResults([
        ..._items(
          responses[0],
        ).map(_candidate).whereType<GeocodeForwardResult>(),
        ..._items(
          responses[1],
        ).map(_candidate).whereType<GeocodeForwardResult>(),
      ]);
    } on TcBackendExternalApiException catch (error) {
      AppLogger.info('GeocodingService', 'search failed: ${error.code.name}');
      return const [];
    } catch (error, stackTrace) {
      AppLogger.error('GeocodingService', error, stackTrace);
      return const [];
    }
  }

  Future<List<GeocodeForwardResult>> geocodeAddressAll(
    String query, [
    String? legacyApiKey,
  ]) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final response = await _backend.getMap(
        '/api/common/geocoding/forward',
        query: {'query': trimmed, 'language': 'ko'},
      );
      return _items(response)
          .map(_candidate)
          .whereType<GeocodeForwardResult>()
          .toList(growable: false);
    } on TcBackendExternalApiException catch (error) {
      AppLogger.info('GeocodingService', 'forward failed: ${error.code.name}');
      return const [];
    } catch (error, stackTrace) {
      AppLogger.error('GeocodingService', error, stackTrace);
      return const [];
    }
  }

  static String cleanDisplayAddress(String formattedAddress) {
    var text = formattedAddress.trim();
    if (text.isEmpty) return text;
    text = text.replaceFirst(RegExp(r'^대한민국\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s+[\d\-]+(?:번지|호)?$'), '').trim();
    return text.isEmpty ? formattedAddress.trim() : text;
  }

  static String approximateRegionName({
    String? level1,
    String? level2,
    String? locality,
  }) {
    if (_hasText(level1) && _hasText(level2)) {
      return '${level1!.trim()} ${level2!.trim()}';
    }
    if (_hasText(level2)) return level2!.trim();
    if (_hasText(locality)) return locality!.trim();
    if (_hasText(level1)) return level1!.trim();
    return '';
  }

  GeocodeForwardResult? _candidate(Map<String, dynamic> json) {
    final latitude = _double(json['latitude']);
    final longitude = _double(json['longitude']);
    final displayName = _string(json['display_name']);
    if (latitude == null || longitude == null || displayName == null) {
      return null;
    }
    return GeocodeForwardResult(
      latitude: latitude,
      longitude: longitude,
      formattedAddress: displayName,
      placeName: _string(json['place_name']),
    );
  }

  LocationSearchSuggestion? _candidateSuggestion(Map<String, dynamic> json) {
    final candidate = _candidate(json);
    if (candidate == null) return null;
    return LocationSearchSuggestion(
      mainText:
          _string(json['place_name']) ??
          cleanDisplayAddress(candidate.formattedAddress),
      secondaryText: candidate.formattedAddress,
      latitude: candidate.latitude,
      longitude: candidate.longitude,
    );
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<LocationSearchSuggestion> _mergeSuggestions(
    List<LocationSearchSuggestion> suggestions,
  ) {
    final merged = <LocationSearchSuggestion>[];
    for (final suggestion in suggestions) {
      final duplicate = merged.any((existing) {
        if (existing.mainText == suggestion.mainText) return true;
        if (existing.hasCoordinates && suggestion.hasCoordinates) {
          return (existing.latitude! - suggestion.latitude!).abs() < 0.002 &&
              (existing.longitude! - suggestion.longitude!).abs() < 0.002;
        }
        return false;
      });
      if (!duplicate) merged.add(suggestion);
    }
    return merged;
  }

  List<GeocodeForwardResult> _mergeForwardResults(
    List<GeocodeForwardResult> results,
  ) {
    final merged = <GeocodeForwardResult>[];
    for (final result in results) {
      final duplicate = merged.any(
        (existing) =>
            (existing.latitude - result.latitude).abs() < 0.002 &&
            (existing.longitude - result.longitude).abs() < 0.002,
      );
      if (!duplicate) merged.add(result);
    }
    return merged;
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;
  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}

class GeocodingResult {
  const GeocodingResult({
    required this.locationName,
    required this.address,
    required this.regionName,
  });

  final String locationName;
  final String address;
  final String regionName;
}

class LocationSearchSuggestion {
  const LocationSearchSuggestion({
    this.placeId,
    required this.mainText,
    this.secondaryText,
    this.latitude,
    this.longitude,
  }) : assert(
         placeId != null || (latitude != null && longitude != null),
         'placeId or coordinates required',
       );

  final String? placeId;
  final String mainText;
  final String? secondaryText;
  final double? latitude;
  final double? longitude;

  bool get hasPlaceId => placeId?.isNotEmpty == true;
  bool get hasCoordinates => latitude != null && longitude != null;

  String get displayLabel {
    final secondary = secondaryText?.trim();
    return secondary?.isNotEmpty == true ? '$mainText · $secondary' : mainText;
  }
}

class GeocodeForwardResult {
  const GeocodeForwardResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    this.placeName,
  });

  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String? placeName;

  String get displayLabel {
    final cleaned = GeocodingService.cleanDisplayAddress(formattedAddress);
    final name = placeName?.trim();
    if (name == null || name.isEmpty || RegExp(r'^[\d\-\s]+$').hasMatch(name)) {
      return cleaned.isNotEmpty ? cleaned : formattedAddress;
    }
    if (cleaned.startsWith(name) || cleaned.contains(name)) return cleaned;
    if (formattedAddress.startsWith(name)) {
      return cleaned.isNotEmpty ? cleaned : formattedAddress;
    }
    return cleaned.isNotEmpty ? '$name · $cleaned' : name;
  }
}
