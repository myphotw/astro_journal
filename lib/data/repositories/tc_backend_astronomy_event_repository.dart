import '../../services/tc_backend_external_api_client.dart';
import '../models/astronomy_event.dart';
import 'astronomy_event_repository.dart';

class TcBackendAstronomyEventRepository implements AstronomyEventRepository {
  const TcBackendAstronomyEventRepository(this._client);

  final TcBackendExternalApiClient _client;

  @override
  Future<List<AstronomyEvent>> getUpcomingEvents({
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String, String>{
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    };
    final response = await _client.getMap(
      '/api/astro/events',
      query: query.isEmpty ? null : query,
    );
    final rawEvents = response['events'];
    if (rawEvents is! List) {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: '천문 이벤트 응답 형식이 올바르지 않습니다.',
      );
    }

    try {
      return List<AstronomyEvent>.unmodifiable(
        rawEvents.map((rawEvent) {
          if (rawEvent is! Map) {
            throw const FormatException('events[] must be a JSON object.');
          }
          return AstronomyEvent.fromJson(Map<String, dynamic>.from(rawEvent));
        }),
      );
    } on FormatException {
      throw const TcBackendExternalApiException(
        code: TcBackendExternalApiErrorCode.malformedResponse,
        message: '천문 이벤트 응답 형식이 올바르지 않습니다.',
      );
    }
  }
}
