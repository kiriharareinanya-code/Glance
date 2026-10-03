// Ported from Lyricify.Lyrics.Helper/Generators/LyricifyLinesGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import 'lrc_generator.dart' show SubLinesOutputType;

class LyricifyLinesGenerator {
  static String generate(
    LyricsData lyricsData, [
    SubLinesOutputType subLinesOutputType = SubLinesOutputType.inMainLine,
  ]) {
    final lines = lyricsData.lines;
    if (lines == null || lines.isEmpty) return '';

    final sb = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (subLinesOutputType == SubLinesOutputType.inDiffLine) {
        _appendLine(sb, line);
        final subLine = line.subLine;
        if (subLine != null) _appendLine(sb, subLine);
      } else {
        final startTimeWithSubLine = line.startTimeWithSubLine;
        if (startTimeWithSubLine != null) {
          _writeLine(sb,
              '[$startTimeWithSubLine,${line.endTimeWithSubLine ?? 0}]${line.fullText}');
        }
      }
    }

    return sb.toString();
  }
}

void _appendLine(StringBuffer sb, LineInfo line) {
  final startTime = line.startTime;
  if (startTime != null) {
    _writeLine(sb, '[$startTime,${line.endTime ?? 0}]${line.text}');
  }
}

void _writeLine(StringBuffer sb, String text) {
  sb.write(text);
  sb.write('\r\n');
}
