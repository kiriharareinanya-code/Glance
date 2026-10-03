// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/Musixmatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//     `StandardizeMusixmatchLyrics(List<ILineInfo>)`  → [standardizeMusixmatchLyricsList]
//     `StandardizeMusixmatchLyrics(SyllableLineInfo)` → [standardizeMusixmatchLyrics]
//   `SyllableWordMerger.Merge(line)` → [SyllableWordMerger.merge]。
library;

import '../../models/line_info.dart';
import '../../models/syllable_info.dart';
import 'syllable_word_merger.dart';

class Musixmatch {
  Musixmatch._();

  static void standardizeMusixmatchLyricsList(List<LineInfo> list) {
    for (final line in list) {
      if (line is SyllableLineInfo) {
        standardizeMusixmatchLyrics(line);
      }
    }
  }

  static void standardizeMusixmatchLyrics(SyllableLineInfo syllableLine) {
    if (syllableLine.syllables.isEmpty ||
        syllableLine.syllables.any((item) => item is! TextSyllableInfo)) {
      return;
    }

    // Musixmatch exposes whitespace as its own timed fragment. Attach it to
    // the previous fragment so the shared merger can use it as a word boundary.
    for (var index = 1; index < syllableLine.syllables.length; index++) {
      final fragment = syllableLine.syllables[index];
      if (_isAllWhiteSpace(fragment.text)) {
        (syllableLine.syllables[index - 1] as TextSyllableInfo).text +=
            syllableLine.syllables[index].text;
        syllableLine.syllables.removeAt(index--);
      }
    }

    SyllableWordMerger.merge(syllableLine);
  }

  static bool _isAllWhiteSpace(String text) {
    for (var i = 0; i < text.length; i++) {
      if (!SyllableWordMerger.isWhiteSpace(text[i])) return false;
    }
    return true;
  }
}
