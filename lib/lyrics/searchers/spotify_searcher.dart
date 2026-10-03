// Ported from Lyricify.Lyrics.Helper/Searchers/SpotifySearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `SearchForResults(track)` / `(track, fullSearch)` → [searchForResultsByTrack]
//
//
library;

import '../models/track_metadata.dart';
import '../providers/web/providers.dart';
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'searchers.dart';
import 'spotify_search_result.dart';

class SpotifySearcher implements ISearcher {
  @override
  String get name => 'Spotify';

  @override
  String get displayName => 'Spotify';

  @override
  Searchers get searcherType => Searchers.spotify;

  @override
  Future<ISearchResult?> searchForResult(TrackMetadata track,
      [MatchType? minimumMatch]) async {
    final results = await searchForResultsByTrack(track);
    if (minimumMatch == null) {
      return results.isEmpty ? null : results.first;
    }
    for (final t in results) {
      if ((t.matchType?.value ?? -1) >= minimumMatch.value) return t;
    }
    return null;
  }

  @override
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]) async {
    try {
      final metadata =
          TrackMultiArtistMetadata.getTrackMultiArtistMetadata(track);
      final song = metadata.title ?? '';
      final artist = metadata.artist ?? '';
      final candidates =
          await Providers.spotifyApi.searchTrackCandidates(song, artist, 20);

      final results = <ISearchResult>[
        for (final t in candidates) SpotifySearchResult.fromTrackCandidate(t)
      ];
      for (final result in results) {
        result.setMatchType(CompareHelper.compareTrack(metadata, result));
      }

      results.sort(
          (x, y) => y.matchType!.value.compareTo(x.matchType!.value));
      return results;
    } catch (e) {
      if (_isUnauthorized(e)) rethrow;
      return <ISearchResult>[];
    }
  }

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    try {
      final candidates = await Providers.spotifyApi
          .searchTrackCandidates(searchString, '', 20);
      if (candidates.isEmpty) return null;

      return <ISearchResult>[
        for (final t in candidates) SpotifySearchResult.fromTrackCandidate(t)
      ];
    } catch (e) {
      if (_isUnauthorized(e)) rethrow;
      return null;
    }
  }

  static bool _isUnauthorized(Object e) =>
      e.runtimeType.toString().startsWith('Unauthorized');
}
