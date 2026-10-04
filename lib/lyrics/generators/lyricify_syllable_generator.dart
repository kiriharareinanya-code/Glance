// Ported from Lyricify.Lyrics.Helper/Generators/LyricifySyllableGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//
// PORT NOTE: 上游 `sb.AppendLine()`（LyricifySyllableGenerator.cs:65）写的是
//   `Environment.NewLine`，在 Windows 上就是 `\r\n`。Dart 侧固定写 `\r\n`
//   （不跟 `Platform.lineTerminator`），这样「生成 → 解析 → 再生成」的往返
//   在任何平台上都是逐字节一致的。
// PORT NOTE: 上游 `sb.Append(item.StartTime)` / `sb.Append(((ISyllableInfo)item).Duration)`
//   （:71-73）的形参是非空 `int`（见 Models/ISyllableInfo.cs），所以这里不需要判空；
//   行头的 `sb.Append(line.LyricsAlignment ...)`（:35-47）写的是常量 3/4/5/6/7/8，
//   `sb.write(int)` 与之等价。
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/syllable_info.dart';

class LyricifySyllableGenerator {
  static String generate(LyricsData lyricsData) {
    final lines = lyricsData.lines;
    if (lines == null || lines.isEmpty) return '';

    final sb = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line is SyllableLineInfo) {
        _appendLine(sb, line);
        final subLine = line.subLine;
        if (subLine is SyllableLineInfo) {
          _appendLine(sb, subLine, true);
        }
      }
    }

    return sb.toString();
  }
}

void _appendLine(StringBuffer sb, SyllableLineInfo line,
    [bool isSubLine = false]) {
  sb.write('[');
  sb.write(isSubLine
      ? switch (line.lyricsAlignment) {
          LyricsAlignment.left => 7,
          LyricsAlignment.right => 8,
          _ => 6,
        }
      : switch (line.lyricsAlignment) {
          LyricsAlignment.left => 4,
          LyricsAlignment.right => 5,
          _ => 3,
        });
  sb.write(']');

  for (final syllable in line.syllables) {
    if (syllable is TextSyllableInfo) {
      _appendSyllable(sb, syllable);
    } else if (syllable is FullSyllableInfo) {
      for (final item in syllable.subItems) {
        _appendSyllable(sb, item);
      }
    }
  }
  sb.write('\r\n');
}

void _appendSyllable(StringBuffer sb, SyllableInfo item) {
  sb.write(item.text);
  sb.write('(');
  sb.write(item.startTime);
  sb.write(',');
  sb.write(item.duration);
  sb.write(')');
}
