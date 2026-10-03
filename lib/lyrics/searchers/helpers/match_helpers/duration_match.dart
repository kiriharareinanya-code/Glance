// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/DurationMatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
library;

///
///
DurationMatchType? compareDuration(int? duration1, int? duration2) {
  if (duration1 == null ||
      duration2 == null ||
      duration1 == 0 ||
      duration2 == 0) {
    return null;
  }

  final diff = (duration1 - duration2).abs();
  if (diff == 0) return DurationMatchType.perfect;
  if (diff < 300) return DurationMatchType.veryHigh;
  if (diff < 700) return DurationMatchType.high;
  if (diff < 1500) return DurationMatchType.medium;
  if (diff < 3500) return DurationMatchType.low;
  return DurationMatchType.noMatch;
}

///
enum DurationMatchType {
  perfect,
  veryHigh,
  high,
  medium,
  low,
  noMatch(-1);

  const DurationMatchType([this.value]);

  final int? value;
}

extension DurationMatchTypeScore on DurationMatchType {
  int get matchScore {
    switch (this) {
      case DurationMatchType.perfect:
        return 7;
      case DurationMatchType.veryHigh:
        return 6;
      case DurationMatchType.high:
        return 5;
      case DurationMatchType.medium:
        return 4;
      case DurationMatchType.low:
        return 2;
      case DurationMatchType.noMatch:
        return 0;
    }
  }
}

///
int matchScoreOfDuration(DurationMatchType? matchType) =>
    matchType?.matchScore ?? 0;
