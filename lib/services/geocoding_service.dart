import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';

/// Google Geocoding API — reverse (coords → address) and forward (address → coords).
class GeocodingService {
  static const _endpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// [lat], [lng] 좌표를 [apiKey]로 조회하여 [GeocodingResult]를 반환한다.
  ///
  /// API 키가 없거나 요청에 실패하면 null을 반환한다.
  Future<GeocodingResult?> getLocationInfo(
    double lat,
    double lng,
    String apiKey,
  ) async {
    if (apiKey.isEmpty) {
      AppLogger.mapApi('GeocodingService: API 키 없음 - 주소 조회 생략');
      return null;
    }

    try {
      AppLogger.mapApi('GeocodingService: 요청 시작 (lat=$lat, lng=$lng)');

      final uri = Uri.parse(
        '$_endpoint?latlng=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
        '&language=ko'
        '&key=$apiKey',
      );

      final sw = Stopwatch()..start();
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      sw.stop();

      AppLogger.mapApi(
        'GeocodingService: 응답 ${response.statusCode} (${sw.elapsedMilliseconds}ms)',
      );

      if (response.statusCode != 200) {
        AppLogger.mapApi('GeocodingService: HTTP 오류 ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String? ?? '';
      if (status != 'OK') {
        AppLogger.mapApi('GeocodingService: API status=$status');
        return null;
      }

      final results = json['results'] as List<dynamic>;
      if (results.isEmpty) {
        AppLogger.mapApi('GeocodingService: 결과 없음');
        return null;
      }

      final result = _buildResult(results);
      if (result != null) {
        AppLogger.mapApi(
          'GeocodingService: 촬영지명=${result.locationName}, 주소=${result.address}',
        );
      }
      return result;
    } catch (e) {
      AppLogger.error('GeocodingService', e);
      debugPrint('GeocodingService: 주소 조회 실패 - $e');
      return null;
    }
  }

  /// Backward compatible: [lat], [lng] 좌표를 짧은 위치명 문자열로 반환한다.
  ///
  /// API 키가 없거나 요청에 실패하면 null을 반환한다.
  Future<String?> getAddress(double lat, double lng, String apiKey) async {
    final result = await getLocationInfo(lat, lng, apiKey);
    return result?.locationName;
  }

  /// 주소/지명 문자열을 좌표로 변환한다. 첫 번째 결과만 반환한다.
  Future<GeocodeForwardResult?> geocodeAddress(
    String query,
    String apiKey,
  ) async {
    final results = await geocodeAddressAll(query, apiKey);
    if (results.isEmpty) return null;
    return results.first;
  }

  /// Places Autocomplete + Geocoding — 입력 중 실시간 지명 제안.
  ///
  /// Autocomplete alone often misses Korean village names (e.g. 계산리);
  /// Geocoding results are merged for administrative/locality coverage.
  Future<List<LocationSearchSuggestion>> autocompleteLocations(
    String query,
    String apiKey,
  ) async {
    final trimmed = query.trim();
    if (apiKey.isEmpty || trimmed.isEmpty) return const [];

    final results = await Future.wait([
      _fetchAutocompletePredictions(trimmed, apiKey),
      _geocodeToSuggestions(trimmed, apiKey),
    ]);

    return _mergeSuggestions([...results[0], ...results[1]]);
  }

  Future<List<LocationSearchSuggestion>> _fetchAutocompletePredictions(
    String query,
    String apiKey,
  ) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
      ).replace(
        queryParameters: {
          'input': query,
          'language': 'ko',
          'components': 'country:kr',
          'location': '37.5,127.0',
          'radius': '500000',
          'key': apiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String? ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        AppLogger.mapApi('GeocodingService: Autocomplete status=$status');
        return const [];
      }

      final predictions = json['predictions'] as List<dynamic>? ?? const [];
      return predictions
          .map(
            (item) => _parseAutocompletePrediction(item as Map<String, dynamic>),
          )
          .whereType<LocationSearchSuggestion>()
          .toList(growable: false);
    } catch (e) {
      AppLogger.error('GeocodingService', e);
      return const [];
    }
  }

  Future<List<LocationSearchSuggestion>> _geocodeToSuggestions(
    String query,
    String apiKey,
  ) async {
    final results = await geocodeAddressAll(query, apiKey);
    return results
        .map(
          (result) => LocationSearchSuggestion(
            mainText: _suggestionTitle(result),
            secondaryText: result.formattedAddress,
            latitude: result.latitude,
            longitude: result.longitude,
          ),
        )
        .toList(growable: false);
  }

  /// 검색 결과 제목 — 번지 숫자만 남지 않도록 정리한다.
  String _suggestionTitle(GeocodeForwardResult result) {
    final place = result.placeName?.trim();
    if (place != null &&
        place.isNotEmpty &&
        !_isBareStreetNumber(place)) {
      return place;
    }
    return cleanDisplayAddress(result.formattedAddress);
  }

  List<LocationSearchSuggestion> _mergeSuggestions(
    List<LocationSearchSuggestion> suggestions,
  ) {
    final merged = <LocationSearchSuggestion>[];
    for (final suggestion in suggestions) {
      final duplicate = merged.any(
        (existing) => _isDuplicateSuggestion(existing, suggestion),
      );
      if (!duplicate) merged.add(suggestion);
    }
    return merged;
  }

  bool _isDuplicateSuggestion(
    LocationSearchSuggestion a,
    LocationSearchSuggestion b,
  ) {
    if (a.mainText == b.mainText) return true;

    if (a.hasCoordinates && b.hasCoordinates) {
      return (a.latitude! - b.latitude!).abs() < 0.002 &&
          (a.longitude! - b.longitude!).abs() < 0.002;
    }

    return false;
  }

  /// 표시용 주소 — 국가명·끝 번지를 제거하고 시/군/구·읍면동을 남긴다.
  ///
  /// 예: `대한민국 경기도 광명시 철산동 6` → `경기도 광명시 철산동`
  static String cleanDisplayAddress(String formattedAddress) {
    var text = formattedAddress.trim();
    if (text.isEmpty) return text;
    text = text.replaceFirst(RegExp(r'^대한민국\s*'), '').trim();
    // 끝의 번지/호수 (6, 123-45, 12번지 등)
    text = text.replaceFirst(RegExp(r'\s+[\d\-]+(?:번지|호)?$'), '').trim();
    if (text.isEmpty) return formattedAddress.trim();
    return text;
  }

  static bool _isBareStreetNumber(String value) {
    return RegExp(r'^[\d\-\s]+$').hasMatch(value.trim());
  }

  /// Autocomplete place_id → 좌표·주소.
  Future<GeocodeForwardResult?> getPlaceDetails(
    String placeId,
    String apiKey,
  ) async {
    if (apiKey.isEmpty || placeId.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json',
      ).replace(
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,formatted_address,name',
          'language': 'ko',
          'key': apiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return null;

      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      return _parsePlaceForwardResult(result);
    } catch (e) {
      AppLogger.error('GeocodingService', e);
      return null;
    }
  }

  LocationSearchSuggestion? _parseAutocompletePrediction(
    Map<String, dynamic> prediction,
  ) {
    final placeId = prediction['place_id'] as String? ?? '';
    if (placeId.isEmpty) return null;

    final structured =
        prediction['structured_formatting'] as Map<String, dynamic>?;
    final mainText = structured?['main_text'] as String? ??
        prediction['description'] as String? ??
        '';
    if (mainText.isEmpty) return null;

    return LocationSearchSuggestion(
      placeId: placeId,
      mainText: mainText,
      secondaryText: structured?['secondary_text'] as String?,
    );
  }

  /// 주소/지명 검색 — Geocoding + Places Text Search 결과를 병합한다.
  Future<List<GeocodeForwardResult>> searchLocationsAll(
    String query,
    String apiKey,
  ) async {
    final trimmed = query.trim();
    if (apiKey.isEmpty || trimmed.isEmpty) return const [];

    final geocode = await geocodeAddressAll(trimmed, apiKey);
    final places = await _searchPlacesAll(trimmed, apiKey);
    return _mergeForwardResults([...geocode, ...places]);
  }

  /// Geocoding API 결과 목록.
  Future<List<GeocodeForwardResult>> geocodeAddressAll(
    String query,
    String apiKey,
  ) async {
    final trimmed = query.trim();
    if (apiKey.isEmpty || trimmed.isEmpty) return const [];

    try {
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {
          'address': trimmed,
          'language': 'ko',
          'region': 'kr',
          'key': apiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return const [];

      final results = json['results'] as List<dynamic>;
      return results
          .map((item) => _parseGeocodeForwardResult(item as Map<String, dynamic>))
          .whereType<GeocodeForwardResult>()
          .toList(growable: false);
    } catch (e) {
      AppLogger.error('GeocodingService', e);
      return const [];
    }
  }

  Future<List<GeocodeForwardResult>> _searchPlacesAll(
    String query,
    String apiKey,
  ) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
      ).replace(
        queryParameters: {
          'query': query,
          'language': 'ko',
          'region': 'kr',
          'key': apiKey,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return const [];

      final results = json['results'] as List<dynamic>;
      return results
          .map((item) => _parsePlaceForwardResult(item as Map<String, dynamic>))
          .whereType<GeocodeForwardResult>()
          .toList(growable: false);
    } catch (e) {
      AppLogger.error('GeocodingService', e);
      return const [];
    }
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

  GeocodeForwardResult? _parseGeocodeForwardResult(Map<String, dynamic> result) {
    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final formatted = result['formatted_address'] as String? ?? '';
    if (formatted.isEmpty) return null;

    return GeocodeForwardResult(
      latitude: (location['lat'] as num).toDouble(),
      longitude: (location['lng'] as num).toDouble(),
      formattedAddress: formatted,
      placeName: _primaryNameFromComponents(result['address_components']),
    );
  }

  GeocodeForwardResult? _parsePlaceForwardResult(Map<String, dynamic> result) {
    final geometry = result['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    if (location == null) return null;

    final formatted = result['formatted_address'] as String? ?? '';
    final name = result['name'] as String? ?? '';
    if (formatted.isEmpty && name.isEmpty) return null;

    return GeocodeForwardResult(
      latitude: (location['lat'] as num).toDouble(),
      longitude: (location['lng'] as num).toDouble(),
      formattedAddress: formatted.isNotEmpty ? formatted : name,
      placeName: name.isNotEmpty ? name : null,
    );
  }

  String? _primaryNameFromComponents(dynamic rawComponents) {
    if (rawComponents is! List<dynamic>) return null;

    String? level1;
    String? level2;
    String? level3;
    String? locality;

    for (final comp in rawComponents) {
      final c = comp as Map<String, dynamic>;
      final types = (c['types'] as List<dynamic>).cast<String>();
      final name = c['long_name'] as String? ?? '';

      if (types.contains('administrative_area_level_1') && level1 == null) {
        level1 = name;
      }
      if (types.contains('administrative_area_level_2') && level2 == null) {
        level2 = name;
      }
      if (types.contains('administrative_area_level_3') && level3 == null) {
        level3 = name;
      }
      if (types.contains('locality') && locality == null) {
        locality = name;
      }
    }

    return level3 ?? locality ?? level2 ?? level1;
  }

  GeocodingResult? _buildResult(List<dynamic> results) {
    String? level1; // 시/도
    String? level2; // 시/군/구
    String? level3; // 읍/면/동
    String? sublocality; // 동/읍/면 (more specific)
    String? locality;

    final firstResult = results.first as Map<String, dynamic>;
    final components = firstResult['address_components'] as List<dynamic>;

    for (final comp in components) {
      final c = comp as Map<String, dynamic>;
      final types = (c['types'] as List<dynamic>).cast<String>();
      final name = c['long_name'] as String? ?? '';

      if (types.contains('administrative_area_level_1') && level1 == null) {
        level1 = name;
      }
      if (types.contains('administrative_area_level_2') && level2 == null) {
        level2 = name;
      }
      if (types.contains('administrative_area_level_3') && level3 == null) {
        level3 = name;
      }
      if (types.contains('sublocality_level_1') && sublocality == null) {
        sublocality = name;
      }
      if (types.contains('locality') && locality == null) {
        locality = name;
      }
    }

    // 전체 주소: level1 + level2 + level3 + sublocality
    final addressParts = [level1, level2, level3, sublocality]
        .whereType<String>()
        .toList();
    final address = addressParts.isNotEmpty ? addressParts.join(' ') : '';

    // 촬영지명: 시·군·구 + 읍면동 (번지만 남지 않도록 address 우선)
    final locationName = address.isNotEmpty
        ? address
        : (sublocality ?? level3 ?? locality ?? level2 ?? level1 ?? '');

    if (locationName.isEmpty && address.isEmpty) return null;

    final regionName = approximateRegionName(
      level1: level1,
      level2: level2,
      locality: locality,
    );

    return GeocodingResult(
      locationName: locationName,
      address: address.isNotEmpty ? address : locationName,
      regionName: regionName.isNotEmpty ? regionName : locationName,
    );
  }

  /// 시/도 + 시/군/구 수준의 대략적인 지역명.
  static String approximateRegionName({
    String? level1,
    String? level2,
    String? locality,
  }) {
    if (level1 != null &&
        level1.trim().isNotEmpty &&
        level2 != null &&
        level2.trim().isNotEmpty) {
      return '${level1.trim()} ${level2.trim()}';
    }
    if (level2 != null && level2.trim().isNotEmpty) return level2.trim();
    if (locality != null && locality.trim().isNotEmpty) return locality.trim();
    if (level1 != null && level1.trim().isNotEmpty) return level1.trim();
    return '';
  }
}

/// Geocoding 조회 결과.
class GeocodingResult {
  const GeocodingResult({
    required this.locationName,
    required this.address,
    required this.regionName,
  });

  /// 가장 상세한 행정구역 이름 (예: 선감동, 서석면).
  final String locationName;

  /// 전체 주소 (예: 경기도 안산시 단원구 선감동).
  final String address;

  /// 대략적인 지역명 (예: 부산광역시 해운대구).
  final String regionName;
}

/// Autocomplete suggestion (place_id resolved on selection).
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

  bool get hasPlaceId => placeId != null && placeId!.isNotEmpty;

  bool get hasCoordinates => latitude != null && longitude != null;

  String get displayLabel {
    final secondary = secondaryText?.trim();
    if (secondary != null && secondary.isNotEmpty) {
      return '$mainText · $secondary';
    }
    return mainText;
  }
}

/// Forward geocoding result (address → coordinates).
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
    if (name == null ||
        name.isEmpty ||
        RegExp(r'^[\d\-\s]+$').hasMatch(name)) {
      return cleaned.isNotEmpty ? cleaned : formattedAddress;
    }
    if (cleaned.startsWith(name) || cleaned.contains(name)) return cleaned;
    if (formattedAddress.startsWith(name)) {
      return cleaned.isNotEmpty ? cleaned : formattedAddress;
    }
    return cleaned.isNotEmpty ? '$name · $cleaned' : name;
  }
}
