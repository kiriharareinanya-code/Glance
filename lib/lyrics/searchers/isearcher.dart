// Ported from Lyricify.Lyrics.Helper/Searchers/ISearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   - `SearchForResults(string searchString)`          → [searchForResults]
//   - `SearchForResults(ITrackMetadata track)`         → [searchForResultsByTrack]
//   - `SearchForResults(ITrackMetadata track, bool fullSearch)` → [searchForResultsByTrack](track, fullSearch)
//   - `SearchForResult(ITrackMetadata track)`          → [searchForResult]
//   - `SearchForResult(ITrackMetadata track, MatchType minimumMatch)` → [searchForResult](track, minimumMatch)
library;

import '../models/track_metadata.dart';
import 'helpers/compare_helper.dart';
import 'searchers.dart';

part 'isearch_result.dart';

abstract class ISearcher {
  String get name;

  String get displayName;

  Searchers get searcherType;

  ///
  Future<ISearchResult?> searchForResult(TrackMetadata track,
      [MatchType? minimumMatch]);

  ///
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]);

  Future<List<ISearchResult>?> searchForResults(String searchString);
}
