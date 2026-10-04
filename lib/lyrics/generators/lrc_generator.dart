// Ported from Lyricify.Lyrics.Helper/Generators/LrcGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//   `StringBuilder` → `StringBuffer`；`sb.AppendLine(x)` → `sb.writeln(x)`。
//   `string.Empty` → `''`。
//
// PORT NOTE: 上游 `sb.AppendLine()`（LrcGenerator.cs:54/61/66）写的是 `Environment.NewLine`，
//   在 Windows 上就是 `\r\n`。Dart 侧固定写 `\r\n`（不跟 `Platform.lineTerminator`），
//   这样「生成 → 解析 → 再生成」的往返在任何平台上都是逐字节一致的。
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../helpers/general/string_helper.dart';

class LrcGenerator {
  /// 生成 LRC 字符串
  /// @param lyricsData 用于生成的源歌词数据
  /// @param endTimeOutputType 作为行末时间的空行的输出类型
  /// @param subLinesOutputType 子行的输出方式
  /// @returns 生成出的 LRC 字符串
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
  // PORT NOTE: 上游是 `if (line.EndTime <= 0) return false;`（LrcGenerator.cs:74），
  // `line.EndTime` 是 `int?`，C# 的 lifted 比较在 null 时结果是 **false**（即不 return），
  // 所以「行本身没有结束时间、但子行有」时上游会继续往下走。写成 `(line.endTime ?? 0) <= 0`
  // 会把 null 当成 0 而提前 return，属于行为差异，这里按上游还原。
  final lineEndTime = line.endTime;
  if (lineEndTime != null && lineEndTime <= 0) return false;
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
