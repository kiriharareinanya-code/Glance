// Ported from Lyricify.Lyrics.Helper/Searchers/SodaMusicSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
// `[for (final a in track.entity?.track?.artists ?? <soda.Artist>[]) a.name]`；
// `(int)Track.Entity.Track.Duration` → `track.entity?.track?.duration ?? 0`
library;

import '../providers/web/sodamusic/response.dart' as soda;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'sodamusic_searcher.dart';

class SodaMusicSearchResult extends ISearchResult {
  SodaMusicSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
  );

  factory SodaMusicSearchResult.fromResultGroupItem(
          soda.ResultGroupItem track) =>
      SodaMusicSearchResult(
        track.entity?.track?.name ?? '',
        [
          for (final a in track.entity?.track?.artists ?? <soda.Artist>[])
            a.name
        ],
        track.entity?.track?.album?.name ?? '',
        null,
        track.entity?.track?.duration ?? 0,
        track.entity?.track?.id ?? '',
      );

  @override
  ISearcher get searcher => SodaMusicSearcher();

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
