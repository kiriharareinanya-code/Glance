// Ported from Lyricify.Lyrics.Helper/Searchers/MusixmatchSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../providers/web/musixmatch/response.dart' as mx;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'musixmatch_searcher.dart';

class MusixmatchSearchResult extends ISearchResult {
  MusixmatchSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
    this.isrc,
    this.vanityId,
  );

  /// Dart DTO
  factory MusixmatchSearchResult.fromTrack(dynamic track) =>
      MusixmatchSearchResult(
        track.trackName as String,
        _splitArtists((track.artistName as String?) ?? ''),
        (track.albumName as String?) ?? '',
        null,
        ((track.trackLength as num?)?.toInt() ?? 0) * 1000,
        (track.trackId as num?)?.toInt() ?? 0,
        (track.trackIsrc as String?) ?? '',
        (track.commontrackVanityId as String?) ?? '',
      );

  static List<String> _splitArtists(String artistName) {
    return artistName
        .split(RegExp(r' feat\. | & '))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  ISearcher get searcher => MusixmatchSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final int id;

  final String isrc;

  @override
  final List<String>? albumArtists;

  @override
  final int? durationMs;

  String vanityId;

  MatchType? _matchType;

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) {
    _matchType = matchType;
  }
}
