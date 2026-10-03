// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/CompareHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   - MatchHelpers/ArtistMatch.cs（CompareArtist + ArtistMatchType + GetMatchScore）
//   - MatchHelpers/NameMatch.cs（CompareName + NameMatchType + GetMatchScore）
//   - MatchHelpers/DurationMatch.cs（CompareDuration + DurationMatchType + GetMatchScore）
//
//
// （Perfect = 100 … NoMatch = -1），`Searcher`/`MusixmatchSearcher`/`SpotifySearcher`
library;

import '../../models/track_metadata.dart';
import '../isearcher.dart';
import 'match_helpers/artist_match.dart';
import 'match_helpers/name_match.dart';
import 'match_helpers/duration_match.dart';

class CompareHelper {
  CompareHelper._();

  ///
  ///
  static MatchType compareTrack(
      TrackMetadata track, ISearchResult searchResult) {
    return compareTrackMultiArtist(
      TrackMultiArtistMetadata.getTrackMultiArtistMetadata(track),
      searchResult,
    );
  }

  ///
  ///
  ///
  static MatchType compareTrackMultiArtist(
      TrackMultiArtistMetadata track, ISearchResult searchResult) {
    final trackMatch = compareName(track.title, searchResult.title);
    final artistMatch =
        compareArtist(track.artists, searchResult.artists);
    final albumMatch = compareName(track.album, searchResult.album);
    final albumArtistMatch = compareArtist(
        track.albumArtists, searchResult.albumArtists);
    final durationMatch = compareDuration(
        track.durationMs, searchResult.durationMs);

    double totalScore = 0;
    totalScore += matchScoreOfName(trackMatch);
    totalScore += matchScoreOfArtist(artistMatch);
    totalScore += matchScoreOfName(albumMatch) * 0.4;
    totalScore += matchScoreOfArtist(albumArtistMatch) * 0.2;
    totalScore += matchScoreOfDuration(durationMatch);

    const double fullScore = (1 + 1 + 0.4 + 0.2 + 1) * 7;
    double availableScore = (1 + 1) * 7.0;
    if (albumMatch != null) availableScore += 0.4 * 7;
    if (albumArtistMatch != null) availableScore += 0.2 * 7;
    if (durationMatch != null) availableScore += 7;
    totalScore *= fullScore / availableScore;

    if (totalScore > 21) return MatchType.perfect;
    if (totalScore > 19) return MatchType.veryHigh;
    if (totalScore > 17) return MatchType.high;
    if (totalScore > 15) return MatchType.prettyHigh;
    if (totalScore > 11) return MatchType.medium;
    if (totalScore > 8) return MatchType.low;
    if (totalScore > 3) return MatchType.veryLow;
    return MatchType.noMatch;
  }

  static ArtistMatchType? compareArtist(
          List<String>? artist1, List<String>? artist2) =>
      compareArtist(artist1, artist2);

  static NameMatchType? compareName(String? name1, String? name2) =>
      compareName(name1, name2);

  static DurationMatchType? compareDuration(int? duration1, int? duration2) =>
      compareDuration(duration1, duration2);
}

///
enum MatchType {
  perfect(100),
  veryHigh(99),
  high(95),
  prettyHigh(90),
  medium(70),
  low(30),
  veryLow(10),
  noMatch(-1);

  const MatchType(this.value);

  final int value;
}

///
class MatchTypeComparer {
  const MatchTypeComparer();

  int compare(MatchType x, MatchType y) {
    return x.value.compareTo(y.value);
  }
}
