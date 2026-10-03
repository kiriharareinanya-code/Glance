// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/SyncDowngrade.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//     `DowngradeToLineSynced(this List<ILineInfo>)` → [downgradeToLineSyncedList]
//     `DowngradeToLineSynced(this ILineInfo)`       → [downgradeToLineSynced]
//   `new FullLineInfo { ... }` / `new LineInfo { ... }` → [FullTextLineInfo] / [TextLineInfo]
//   `new Dictionary<string, string>(full.Translations)` → `Map<String, String>.of(...)`。
//   `line is IFullLineInfo` → `line is FullLineInfoMixin`（`FullTextLineInfo` /
library;

import '../../models/line_info.dart';

class SyncDowngrade {
  SyncDowngrade._();

  static void downgradeToLineSyncedList(List<LineInfo> list) {
    if (list.isEmpty) return;

    for (var i = 0; i < list.length; i++) {
      list[i] = downgradeToLineSynced(list[i]);
    }
  }

  static LineInfo downgradeToLineSynced(LineInfo line) {
    var sub = line.subLine;
    if (sub != null) {
      sub = downgradeToLineSynced(sub);
    }

    if (line is TextLineInfo) {
      line.subLine = sub;
      return line;
    }

    if (line is SyllableLineInfo) {
      final syllables = line.syllables;
      if (syllables.isEmpty) {
        line.subLine = sub;
        return line;
      }

      final text = line.text;
      final start = syllables.first.startTime;
      final end = syllables.last.endTime;

      if (line is FullLineInfoMixin) {
        final full = line as FullLineInfoMixin;
        final downgradedFull = FullTextLineInfo()
          ..text = text
          ..startTime = start
          ..endTime = end
          ..lyricsAlignment = line.lyricsAlignment
          ..subLine = sub
          ..pronunciation = full.pronunciation
          ..translations = Map<String, String>.of(full.translations);

        return downgradedFull;
      }

      final downgraded = TextLineInfo()
        ..text = text
        ..startTime = start
        ..endTime = end
        ..lyricsAlignment = line.lyricsAlignment
        ..subLine = sub;

      return downgraded;
    }

    return line;
  }
}
