// Ported from Lyricify.Lyrics.Helper/Helpers/SearchHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   - `Search(ITrackMetadata, Searchers)` / `Search(ITrackMetadata, Searchers, MatchType)`
//   - `Search(ITrackMetadata, ISearcher)` / `Search(ITrackMetadata, ISearcher, MatchType)`
library;

import '../models/track_metadata.dart';
import '../searchers/helpers/compare_helper.dart';
import '../searchers/isearcher.dart';
import '../searchers/searchers.dart';
import '../searchers/searchers_helper.dart';

class SearchHelper {
  SearchHelper._();

  ///
  static Future<ISearchResult?> search(TrackMetadata track, Searchers searcher,
          [MatchType? minimumMatch]) =>
      searchWithSearcher(
          track, SearchersHelper.getSearcher(searcher), minimumMatch);

  ///
  static Future<ISearchResult?> searchWithSearcher(
          TrackMetadata track, ISearcher searcher,
          [MatchType? minimumMatch]) =>
      searcher.searchForResult(track, minimumMatch);
}
