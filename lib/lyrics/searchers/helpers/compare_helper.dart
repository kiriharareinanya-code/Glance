// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/CompareHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   - MatchHelpers/ArtistMatch.cs（CompareArtist + artist_match.ArtistMatchType + GetMatchScore）
//   - MatchHelpers/NameMatch.cs（CompareName + name_match.NameMatchType + GetMatchScore）
//   - MatchHelpers/DurationMatch.cs（CompareDuration + duration_match.DurationMatchType + GetMatchScore）
//
//
// （Perfect = 100 … NoMatch = -1），`Searcher`/`MusixmatchSearcher`/`SpotifySearcher`
library;


import '../../models/track_metadata.dart';
import '../isearcher.dart';
import 'match_helpers/artist_match.dart' as artist_match;
import 'match_helpers/name_match.dart' as name_match;
import 'match_helpers/duration_match.dart' as duration_match;
typedef MatchTypeMatch = name_match.NameMatchType;

class CompareHelper {
  CompareHelper._();

  /// 比较曲目匹配程度
  /// @param track 原曲目
  /// @param searchResult 搜索得到的曲目
  /// @returns 曲目匹配程度
  static MatchType compareTrack(
      TrackMetadata track, ISearchResult searchResult) {
    return compareTrackMultiArtist(
      TrackMultiArtistMetadata.getTrackMultiArtistMetadata(track),
      searchResult,
    );
  }

  ///
  ///
  static MatchType compareTrackMultiArtist(
      TrackMultiArtistMetadata track, ISearchResult searchResult) {
    final trackMatch = name_match.compareName(track.title, searchResult.title);
    final artistMatch =
        artist_match.compareArtist(track.artists, searchResult.artists);
    var albumMatch = name_match.compareName(track.album, searchResult.album);
    // 翻译歌名的兜底：播放标题里的**语言版本标记**（Chinese Ver. 等）
    // 在候选的专辑名里往往能对上——实测《昔涟》的专辑叫
    // 「崩坏星穹铁道-昔涟 Ripples of Past Reverie」，中英文都在。
    // 标题对不上时，用「语言标记 + 专辑」把译名版认出来。
    if (trackMatch != null && trackMatch != MatchTypeMatch.perfect) {
      if (_albumConfirmsTitle(track, searchResult)) {
        albumMatch = MatchTypeMatch.perfect;
      }
    }
    final albumArtistMatch = artist_match.compareArtist(
        track.albumArtists, searchResult.albumArtists);
    final durationMatch = duration_match.compareDuration(
        track.durationMs, searchResult.durationMs);

    // **时长否决闸**（上游没有，见下面说明）。
    //
    // 上游把时长当成一个普通加权项参与总分，问题是**归一化会把它稀释掉**：
    // 时长差 75.7 秒 → `noMatch` → 时长得分 0，但标题 7 + 歌手 7 = 14，
    // `availableScore` 缩到 16.6 后 `14 × 25.2/16.6 = 21.2 > 21`，
    // **照样判成 Perfect**。实测《阳光下的星星》（207.8s）匹配到 283.5s
    // 的现场版仍拿 `prettyHigh`，于是歌词被取走并写进缓存——但行时间戳在
    // 4 分钟之后，歌才 3:52，用户看到的是"只有开头几行"。
    //
    // 时长差大到一定程度，就不是"同一首歌的不同版本"了（现场版、加速版、
    //  remix 通常也就差 10~20%）。差 25% 以上基本可以断定是**另一首歌**
    // （同名不同曲在网易云上非常多）。这种候选必须直接否掉，不能再指望
    // 分数体系去表达"标题对了但时长完全不对"这种自相矛盾的证据。
    if (durationMatch == duration_match.DurationMatchType.noMatch &&
        _durationDiffRatioExceeds(track.durationMs, searchResult.durationMs,
            0.25)) {
      return MatchType.noMatch;
    }

    double totalScore = 0;
    totalScore += name_match.matchScoreOfName(trackMatch);
    totalScore += artist_match.matchScoreOfArtist(artistMatch);
    totalScore += name_match.matchScoreOfName(albumMatch) * 0.4;
    totalScore += artist_match.matchScoreOfArtist(albumArtistMatch) * 0.2;
    totalScore += duration_match.matchScoreOfDuration(durationMatch);

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

  /// 时长差是否超过**相对比例** [ratio]。
  ///
  /// 用相对值而不是绝对值，因为"差多少算太多"取决于歌长：3 分钟的歌差
  /// 30 秒是 17%（可疑），但 8 分钟的协奏曲差 30 秒只有 6%（正常）。
  /// 取 `min(d1, d2)` 做分母——候选比原曲短很多时（如 8 分钟原曲 vs
  /// 3 分钟剪辑版，差 62%）判定要更严。
  static bool _durationDiffRatioExceeds(int? d1, int? d2, double ratio) {
    if (d1 == null || d2 == null || d1 == 0 || d2 == 0) return false;
    final shorter = d1 < d2 ? d1 : d2;
    return (d1 - d2).abs() / shorter > ratio;
  }

  /// 候选的专辑名能否佐证"这就是同一首歌的译名版"。
  ///
  /// 翻译歌名场景下标题永远对不上（`昔涟` vs `Ripples of Past Reverie`），
  /// 但**专辑名往往把两个名字都写上**：实测网易云上《昔涟》的专辑叫
  /// 「崩坏星穹铁道-昔涟 Ripples of Past Reverie」。所以拿去掉版本后缀的
  /// 标题主体去专辑名里找，命中就说明候选是同一首歌的另一个语言版本。
  static bool _albumConfirmsTitle(
      TrackMultiArtistMetadata track, ISearchResult result) {
    final album = result.album.toLowerCase();
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
  static artist_match.ArtistMatchType? compareArtist(
          List<String>? artist1, List<String>? artist2) =>
      artist_match.compareArtist(artist1, artist2);

  static name_match.NameMatchType? compareName(String? name1, String? name2) =>
      name_match.compareName(name1, name2);

  static duration_match.DurationMatchType? compareDuration(int? duration1, int? duration2) =>
      duration_match.compareDuration(duration1, duration2);
}

  /// 曲目匹配程度
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

/// 曲目匹配程度比较器
class MatchTypeComparer {
  const MatchTypeComparer();

  int compare(MatchType x, MatchType y) {
    return x.value.compareTo(y.value);
  }
}
