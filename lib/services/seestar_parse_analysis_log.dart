/// EXIF Debug 등 화면 표시용 parse() 단계 로그 버퍼.
class SeestarParseAnalysisLog {
  SeestarParseAnalysisLog(this.buffer);

  final StringBuffer buffer;

  void writeln(String source, String message) {
    buffer.writeln('[$source] $message');
  }
}
