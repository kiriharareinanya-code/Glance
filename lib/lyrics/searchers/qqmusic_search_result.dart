// Ported from Lyricify.Lyrics.Helper/Searchers/QQMusicSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../providers/web/qqmusic/response.dart' as qq;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'qqmusic_searcher.dart';

class QQMusicSearchResult extends ISearchResult {
  QQMusicSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
    this.mid,
  );

  /// Ported from Lyricify.Lyrics.Helper/Searchers/QQMusicSearchResult.cs (Apache-2.0)
  factory QQMusicSearchResult.fromSong(qq.Song song) => QQMusicSearchResult(
        song.title,
        [for (final s in song.singer ?? <qq.Singer>[]) s.name],
        song.album?.title ?? '',
        null,
        song.interval * 1000,
        song.id,
        song.mid,
      );

  @override
  ISearcher get searcher => QQMusicSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final String id;

  final String mid;

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
