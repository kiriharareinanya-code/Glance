// Ported from Lyricify.Lyrics.Helper/Generators/YrcGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//
// PORT NOTE: 上游 `sb.AppendLine()`（YrcGenerator.cs:55）写的是 `Environment.NewLine`，
//   在 Windows 上就是 `\r\n`。Dart 侧固定写 `\r\n`（不跟 `Platform.lineTerminator`），
//   这样「生成 → 解析 → 再生成」的往返在任何平台上都是逐字节一致的。
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/syllable_info.dart';

class YrcGenerator {
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
  // 添加行信息（YrcGenerator.cs:33-38）
  sb.write('[');
  // PORT NOTE: 上游是 `sb.Append(line.StartTime)` / `sb.Append(((ILineInfo)line).Duration)`，
  // 形参是 `int?`。C# 的 `StringBuilder.Append(int?)` 在 null 时**什么都不追加**；
  // Dart 的 `sb.write(null)` 会写出字面量 "null"。这里显式还原上游的 null → 空串行为。
  final startTime = line.startTime;
  if (startTime != null) sb.write(startTime);
  sb.write(',');
  final duration = line.duration;
  if (duration != null) sb.write(duration);
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
  sb.write('(');
  sb.write(item.startTime);
  sb.write(',');
  sb.write(item.duration);
  sb.write(',0)');
  sb.write(item.text);
}
