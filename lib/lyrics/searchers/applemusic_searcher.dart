// Ported from Lyricify.Lyrics.Helper/Searchers/AppleMusicSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
// `result?.results?.songs?.data`；`songs.Length == 0` → `songs.isEmpty`。
library;

import '../providers/web/providers.dart';
import 'applemusic_search_result.dart';
import 'isearcher.dart';
import 'searcher.dart';
import 'searchers.dart';

class AppleMusicSearcher extends Searcher {
  @override
  String get name => 'AppleMusic';

  @override
  String get displayName => 'Apple Music';

  @override
  Searchers get searcherType => Searchers.appleMusic;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    try {
      final result = await Providers.appleMusicApi.search(searchString, 20);
      final songs = result?.results?.songs?.data;

      if (songs == null || songs.isEmpty) return null;

      final list = <ISearchResult>[];
      for (final song in songs) {
        list.add(AppleMusicSearchResult.fromSongData(song));
      }

      return list;
    } catch (_) {
      return null;
    }
  }
}
