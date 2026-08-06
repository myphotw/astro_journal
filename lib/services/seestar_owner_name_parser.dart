import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';
import 'seestar_json_parser.dart';

/// EXIF CameraOwnerName / OwnerName 태그에 저장된 Seestar JSON을 파싱한다.
class SeestarOwnerNameParser {
  const SeestarOwnerNameParser();

  static const _jsonParser = SeestarJsonParser();

  SeestarMetadata? parse(
    String? ownerNameRaw, {
    String source = 'CameraOwnerName',
    StringBuffer? analysisLog,
  }) {
    if (ownerNameRaw == null || ownerNameRaw.trim().isEmpty) {
      AppLogger.metadata('SeestarOwnerNameParser', '$source 입력 없음');
      return null;
    }

    AppLogger.metadata('SeestarOwnerNameParser', '$source Found');
    final jsonBlock = SeestarJsonParser.extractJsonBlock(ownerNameRaw);
    if (jsonBlock == null) {
      AppLogger.metadata('SeestarOwnerNameParser', '$source JSON 블록 추출 실패');
      return null;
    }

    AppLogger.metadata(
      'SeestarOwnerNameParser',
      '$source JSON 블록 추출 완료 (길이=${jsonBlock.length})',
    );
    return _jsonParser.parse(
      jsonBlock,
      source: source,
      analysisLog: analysisLog,
    );
  }
}
