// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/Yrc.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//     `StandardizeYrcLyrics(List<ILineInfo>)`  → [standardizeYrcLyricsList]
//     `StandardizeYrcLyrics(SyllableLineInfo)` → [standardizeYrcLyrics]
//
library;

import '../../models/line_info.dart';
import '../../models/syllable_info.dart';

class Yrc {
  Yrc._();

  static void standardizeYrcLyricsList(List<LineInfo> list) {
    for (final line in list) {
      if (line is SyllableLineInfo) {
        standardizeYrcLyrics(line);
      }
    }
  }

  ///
  static void standardizeYrcLyrics(SyllableLineInfo line) {
    final list = line.syllables;

    while (list.last.text == ' ') {
      list.removeAt(list.length - 1);
    }

    for (var i = 0; i < list.length; i++) {
      if (list[i].text.isEmpty) {
        list.removeAt(i);
        i--;
        continue;
      }

      if (list[i].text == ' ') {
        if (i - 1 >= 0) {
          (list[i - 1] as TextSyllableInfo).text += list[i].text;
        }

        list.removeAt(i);
        i--;
        continue;
      }

      if (i > 0 &&
          list[i].text.length <= 2 &&
          (list[i].text[0] == ',' ||
              list[i].text[0] == '.' ||
              list[i].text[0] == '?' ||
              list[i].text[0] == '!' ||
              list[i].text[0] == '"')) {
        if (i - 1 >= 0) {
          (list[i - 1] as TextSyllableInfo).text += list[i].text;
        }

        list.removeAt(i);
        i--;
        continue;
      }
    }
  }
}
