import '../data/models/seestar_metadata.dart';
import 'app_logger.dart';
import 'seestar_maker_note_parser.dart';
import 'seestar_owner_name_parser.dart';

/// MakerNote / CameraOwnerName JSON 파싱 파이프라인.
///
/// 실제 JSON 파싱은 [SeestarJsonParser.parse] (via MakerNote/OwnerName parser)에서 수행한다.
class SeestarMetadataPipeline {
  const SeestarMetadataPipeline({
    SeestarMakerNoteParser? makerNoteParser,
    SeestarOwnerNameParser? ownerNameParser,
  })  : _makerNoteParser = makerNoteParser ?? const SeestarMakerNoteParser(),
        _ownerNameParser = ownerNameParser ?? const SeestarOwnerNameParser();

  static const _makerNoteParserName = 'SeestarMakerNoteParser.parse';
  static const _ownerNameParserName = 'SeestarOwnerNameParser.parse';
  static const _jsonParserName = 'SeestarJsonParser.parse';

  final SeestarMakerNoteParser _makerNoteParser;
  final SeestarOwnerNameParser _ownerNameParser;

  SeestarMetadata? parseMakerNote(String? raw, {StringBuffer? analysisLog}) {
    if (raw == null || raw.trim().isEmpty) {
      AppLogger.metadata('Pipeline', 'MakerNote Skip (raw empty)');
      return null;
    }

    AppLogger.metadata('Pipeline', 'Calling $_makerNoteParserName');
    AppLogger.metadata('Pipeline', 'JSON parser: $_jsonParserName');
    final result = _makerNoteParser.parse(raw, analysisLog: analysisLog);
    _logParsedResult('MakerNote', result);
    if (result != null) {
      AppLogger.metadata('Pipeline', 'Parser Success');
    } else {
      AppLogger.metadata('Pipeline', 'Parser Fail');
    }
    return result;
  }

  SeestarMetadata? parseCameraOwnerName(String? raw, {StringBuffer? analysisLog}) {
    if (raw == null || raw.trim().isEmpty) {
      AppLogger.metadata('Pipeline', 'CameraOwnerName Skip (raw empty)');
      return null;
    }

    AppLogger.metadata('Pipeline', 'Calling $_ownerNameParserName');
    AppLogger.metadata('Pipeline', 'JSON parser: $_jsonParserName');
    final result = _ownerNameParser.parse(
      raw,
      source: 'CameraOwnerName',
      analysisLog: analysisLog,
    );
    _logParsedResult('CameraOwnerName', result);
    if (result != null) {
      AppLogger.metadata('Pipeline', 'Parser Success');
    } else {
      AppLogger.metadata('Pipeline', 'Parser Fail');
    }
    return result;
  }

  void _logParsedResult(String source, SeestarMetadata? metadata) {
    if (metadata == null) {
      AppLogger.metadata('Pipeline', 'Parsed Result ($source): null');
      return;
    }

    AppLogger.metadata('Pipeline', 'Parsed Result ($source)');
    AppLogger.metadata('Pipeline', '  target=${metadata.objName ?? "-"}');
    AppLogger.metadata('Pipeline', '  date=${metadata.date ?? "-"}');
    AppLogger.metadata('Pipeline', '  lat=${metadata.lat?.toStringAsFixed(6) ?? "-"}');
    AppLogger.metadata('Pipeline', '  lng=${metadata.lng?.toStringAsFixed(6) ?? "-"}');
    AppLogger.metadata('Pipeline', '  stack=${metadata.stackNum ?? "-"}');
    AppLogger.metadata('Pipeline', '  exp=${metadata.expSec ?? "-"}');
    AppLogger.metadata('Pipeline', '  total=${metadata.totExpSec ?? metadata.calculatedTotExpSec ?? "-"}');
    AppLogger.metadata('Pipeline', '  creator=${metadata.creator ?? "-"}');
  }
}
