import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';
import 'seestar_json_parser.dart';

/// EXIF MakerNote 태그에 저장된 Seestar JSON을 파싱한다.
class SeestarMakerNoteParser {
  const SeestarMakerNoteParser();

  static const _jsonParser = SeestarJsonParser();

  SeestarMetadata? parse(
    String? makerNoteRaw, {
    StringBuffer? analysisLog,
  }) {
    if (makerNoteRaw == null || makerNoteRaw.trim().isEmpty) {
      AppLogger.metadata('SeestarMakerNoteParser', 'MakerNote 입력 없음');
      return null;
    }

    AppLogger.metadata('SeestarMakerNoteParser', 'MakerNote Found');
    final jsonBlock = SeestarJsonParser.extractJsonBlock(makerNoteRaw);
    if (jsonBlock == null) {
      AppLogger.metadata('SeestarMakerNoteParser', 'MakerNote JSON 블록 추출 실패');
      return null;
    }

    AppLogger.metadata(
      'SeestarMakerNoteParser',
      'MakerNote JSON 블록 추출 완료 (길이=${jsonBlock.length})',
    );
    return _jsonParser.parse(
      jsonBlock,
      source: 'MakerNote',
      analysisLog: analysisLog,
    );
  }
}
