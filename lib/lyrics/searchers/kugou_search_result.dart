// Ported from Lyricify.Lyrics.Helper/Searchers/KugouSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
// `song.SingerName.Split('、')` → `song.singerName.split('、')`
library;

import '../providers/web/kugou/response.dart' as kg;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'kugou_searcher.dart';

class KugouSearchResult extends ISearchResult {
  KugouSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.hash,
  );

  ///
  factory KugouSearchResult.fromSong(kg.InfoItem song) => KugouSearchResult(
        song.songName,
        song.singerName.split('、'),
        song.albumName, // 很可能会包含中文译名
        null,
        song.duration * 1000,
        song.hash,
      );

  @override
  ISearcher get searcher => KugouSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final String hash;

  @override
  final List<String>? albumArtists;

  @override
  final int? durationMs;

  MatchType? _matchType;

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) {
    _matchType = matchType;
  }
}
