// Ported from Lyricify.Lyrics.Helper/Generators/LrcGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//   `StringBuilder` → `StringBuffer`；`sb.AppendLine(x)` → `sb.writeln(x)`。
//   `string.Empty` → `''`。
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../helpers/general/string_helper.dart';

class LrcGenerator {
  ///
  static String generate(
    LyricsData lyricsData, [
    EndTimeOutputType endTimeOutputType = EndTimeOutputType.huge,
    SubLinesOutputType subLinesOutputType = SubLinesOutputType.inMainLine,
  ]) {
    final lines = lyricsData.lines;
    if (lines == null || lines.isEmpty) return '';

    final sb = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (subLinesOutputType == SubLinesOutputType.inDiffLine) {
        _appendLine(sb, line);
        if (_shouldAddLine(lines, line, false, i, endTimeOutputType)) {
          _appendEmptyLine(sb, line.endTime!);
        }

        final subLine = line.subLine;
        if (subLine != null) {
          _appendLine(sb, subLine);
          if (_shouldAddLine(lines, subLine, false, i, endTimeOutputType)) {
            _appendEmptyLine(sb, subLine.endTime!);
          }
        }
      } else {
        _appendLineWithSub(sb, line);
        if (_shouldAddLine(lines, line, true, i, endTimeOutputType)) {
          _appendEmptyLine(sb, line.endTimeWithSubLine!);
        }
      }
    }

    return sb.toString();
  }
}

void _appendLine(StringBuffer sb, LineInfo line) {
  final startTime = line.startTime;
  if (startTime == null) return;
  _writeLine(sb,
      '[${StringHelper.formatTimeMsToTimestampString(startTime)}]${line.text}');
}

void _appendLineWithSub(StringBuffer sb, LineInfo line) {
  final startTime = line.startTimeWithSubLine;
  if (startTime == null) return;
  _writeLine(sb,
      '[${StringHelper.formatTimeMsToTimestampString(startTime)}]${line.fullText}');
}

void _appendEmptyLine(StringBuffer sb, int timeStamp) {
  _writeLine(sb, '[${StringHelper.formatTimeMsToTimestampString(timeStamp)}]');
}

bool _shouldAddLine(List<LineInfo> lines, LineInfo line, bool withSub, int index,
    EndTimeOutputType endTimeOutputType) {
  final endTime = withSub ? line.endTimeWithSubLine : line.endTime;
  if (endTime == null) return false;
  if ((line.endTime ?? 0) <= 0) return false;
  if (endTimeOutputType == EndTimeOutputType.all) return true;
  if (endTimeOutputType == EndTimeOutputType.huge) {
    if (index + 1 >= lines.length) return true;
    final nextStart = lines[index + 1].startTimeWithSubLine;
    if (nextStart != null && nextStart - endTime > 5000) return true;
  }
  return false;
}

void _writeLine(StringBuffer sb, String text) {
  sb.write(text);
  sb.write('\r\n');
}

enum EndTimeOutputType {
  none,

  huge,

  all,
}

enum SubLinesOutputType {
  inMainLine,

  inDiffLine,
}
