// Ported from Lyricify.Lyrics.Helper/Helpers/OffsetHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//     `AddOffset(LineInfo, int)`             → [addOffsetTextLine]
//     `AddOffset(SyllableLineInfo, int)`     → [addOffsetSyllableLine]
//
//
library;

import '../models/line_info.dart';
import '../models/syllable_info.dart';

class OffsetHelper {
  OffsetHelper._();

  static void addOffset(List<LineInfo> lines, int offset) {
    for (final line in lines) {
      addOffsetLine(line, offset);
    }
  }

  ///
  static void addOffsetLine(LineInfo line, int offset) {
    if (line is SyllableLineInfo) {
      addOffsetSyllableLine(line, offset);
    } else if (line is TextLineInfo) {
      addOffsetTextLine(line, offset);
    }
  }

  static void addOffsetTextLine(TextLineInfo line, int offset) {
    final startTime = line.startTime;
    if (startTime != null) line.startTime = startTime - offset;

    final endTime = line.endTime;
    if (endTime != null) line.endTime = endTime - offset;
  }

  static void addOffsetSyllableLine(SyllableLineInfo line, int offset) {
    final syllables = line.syllables;
    for (final syllable in syllables) {
      if (syllable is TextSyllableInfo) {
        syllable.startTime -= offset;
        syllable.endTime -= offset;
      } else if (syllable is FullSyllableInfo) {
        for (final subItem in syllable.subItems) {
          subItem.startTime -= offset;
          subItem.endTime -= offset;
        }
      }
    }
  }
}
