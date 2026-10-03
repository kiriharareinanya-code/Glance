// Ported from Lyricify.Lyrics.Helper/Generators/KrcGenerator.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//   `StringBuilder` → `StringBuffer`；`sb.AppendLine(x)` → `sb.writeln(x)`。
library;

import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/syllable_info.dart';

class KrcGenerator {
  ///
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
  sb.write(line.startTime);
  sb.write(',');
  sb.write(line.duration);
  sb.write(']');

  for (final syllable in line.syllables) {
    if (syllable is TextSyllableInfo) {
      _appendSyllable(sb, syllable, line.startTime!);
    } else if (syllable is FullSyllableInfo) {
      for (final item in syllable.subItems) {
        _appendSyllable(sb, item, line.startTime!);
      }
    }
  }
  sb.write('\r\n');
}

void _appendSyllable(StringBuffer sb, SyllableInfo item, int startTime) {
  sb.write('<');
  sb.write(item.startTime - startTime);
  sb.write(',');
  sb.write(item.duration);
  sb.write(',0>');
  sb.write(item.text);
}
