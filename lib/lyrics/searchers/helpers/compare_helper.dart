// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/CompareHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   - MatchHelpers/ArtistMatch.cs（CompareArtist + artistMatchHelper.ArtistMatchType + GetMatchScore）
//   - MatchHelpers/NameMatch.cs（CompareName + nameMatchHelper.NameMatchType + GetMatchScore）
//   - MatchHelpers/DurationMatch.cs（CompareDuration + durationMatchHelper.DurationMatchType + GetMatchScore）
//
//
// （Perfect = 100 … NoMatch = -1），`Searcher`/`MusixmatchSearcher`/`SpotifySearcher`
library;


import '../../models/track_metadata.dart';
import '../isearcher.dart';
import 'match_helpers/artist_match.dart' as artistMatchHelper;
import 'match_helpers/name_match.dart' as nameMatchHelper;
import 'match_helpers/duration_match.dart' as durationMatchHelper;
typedef MatchTypeMatch = nameMatchHelper.NameMatchType;

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
    final trackMatch = nameMatchHelper.compareName(track.title, searchResult.title);
    final artistMatch =
        artistMatchHelper.compareArtist(track.artists, searchResult.artists);
    var albumMatch = nameMatchHelper.compareName(track.album, searchResult.album);
    // 翻译歌名的兜底：播放标题里的**语言版本标记**（Chinese Ver. 等）
    // 在候选的专辑名里往往能对上——实测《昔涟》的专辑叫
    // 「崩坏星穹铁道-昔涟 Ripples of Past Reverie」，中英文都在。
    // 标题对不上时，用「语言标记 + 专辑」把译名版认出来。
    if (trackMatch != null && trackMatch != MatchTypeMatch.perfect) {
      if (_albumConfirmsTitle(track, searchResult)) {
        albumMatch = MatchTypeMatch.perfect;
      }
    }
    final albumArtistMatch = artistMatchHelper.compareArtist(
        track.albumArtists, searchResult.albumArtists);
    final durationMatch = durationMatchHelper.compareDuration(
        track.durationMs, searchResult.durationMs);

    double totalScore = 0;
    totalScore += nameMatchHelper.matchScoreOfName(trackMatch);
    totalScore += artistMatchHelper.matchScoreOfArtist(artistMatch);
    totalScore += nameMatchHelper.matchScoreOfName(albumMatch) * 0.4;
    totalScore += artistMatchHelper.matchScoreOfArtist(albumArtistMatch) * 0.2;
    totalScore += durationMatchHelper.matchScoreOfDuration(durationMatch);

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

  /// 候选的专辑名能否佐证"这就是同一首歌的译名版"。
  ///
  /// 翻译歌名场景下标题永远对不上（`昔涟` vs `Ripples of Past Reverie`），
  /// 但**专辑名往往把两个名字都写上**：实测网易云上《昔涟》的专辑叫
  /// 「崩坏星穹铁道-昔涟 Ripples of Past Reverie」。所以拿去掉版本后缀的
  /// 标题主体去专辑名里找，命中就说明候选是同一首歌的另一个语言版本。
  static bool _albumConfirmsTitle(
      TrackMultiArtistMetadata track, ISearchResult result) {
    final album = (result.album ?? '').toLowerCase();
    if (album.isEmpty) return false;
    // 标题主体：去掉 ` - xxx` / `(xxx)` 之类的尾巴
    final base = (track.title ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s*[-(（\[【].*$'), '')
        .trim();
    if (base.length < 4) return false;
    return album.contains(base);
  }

  // 这三个是对上游 `CompareHelper.CompareXxx` 的转发：它们必须转到
  // match_helpers 里的顶层函数。早先去掉 import 前缀时误写成自己调自己，
  // 导致 compareTrack 一进来就无限递归（Stack Overflow）。
  static artistMatchHelper.ArtistMatchType? compareArtist(
          List<String>? artist1, List<String>? artist2) =>
      artistMatchHelper.compareArtist(artist1, artist2);

  static nameMatchHelper.NameMatchType? compareName(String? name1, String? name2) =>
      nameMatchHelper.compareName(name1, name2);

  static durationMatchHelper.DurationMatchType? compareDuration(int? duration1, int? duration2) =>
      durationMatchHelper.compareDuration(duration1, duration2);
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
