// Ported from Lyricify.Lyrics.Helper/Searchers/NeteaseSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../providers/web/netease/response.dart' as ne;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'netease_searcher.dart';

class NeteaseSearchResult extends ISearchResult {
  NeteaseSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
  );

  factory NeteaseSearchResult.fromSong(ne.Song song) => NeteaseSearchResult(
        song.name,
        [for (final s in song.artists ?? <ne.Ar>[]) s.name],
        song.album?.name ?? '',
        null,
        song.duration,
        song.id,
      );

  @override
  ISearcher get searcher => NeteaseSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final String id;

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
