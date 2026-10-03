// Ported from Lyricify.Lyrics.Helper/Searchers/SpotifySearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// （`(string,string[],string,string[]?,int?,string)`、`(SearchTrackItem track)`、
//
// `string[]? AlbumArtists` → `List<String>? albumArtists`。
//
//
// `ArtistHelper.toChineselizeArtists(List<String>)`。
library;

import '../providers/web/spotify/models.dart' as sp;
import 'helpers/artist_helper.dart' as artist_helper;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'spotify_searcher.dart';

class SpotifySearchResult extends ISearchResult {
  SpotifySearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
  );

  factory SpotifySearchResult.fromSearchTrackItem(sp.SearchTrackItem track) =>
      SpotifySearchResult(
        track.name,
        [
          for (final t in track.artists ?? <sp.SearchArtistItem>[])
            if (!_isNullOrWhiteSpace(t.name)) t.name
        ],
        track.album?.name ?? '',
        track.album?.artists == null
            ? null
            : [
                for (final t in track.album!.artists!)
                  if (!_isNullOrWhiteSpace(t.name)) t.name
              ],
        track.durationMs,
        track.id,
      );

  factory SpotifySearchResult.fromTrackCandidate(
          sp.SpotifyTrackCandidate track) =>
      SpotifySearchResult(
        track.title,
        _isNullOrWhiteSpace(track.artistName)
            ? <String>[]
            : artist_helper.ArtistHelper.toChineselizeArtists(
                track.artistName
                    .split(', ')
                    .where((s) => s.isNotEmpty)
                    .toList()),
        track.albumName,
        null,
        track.durationMs ?? 0,
        track.id,
      );

  /// C# `string.IsNullOrWhiteSpace(string?)`。
  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;

  @override
  ISearcher get searcher => SpotifySearcher();

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
