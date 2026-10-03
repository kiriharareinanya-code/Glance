// Ported from Lyricify.Lyrics.Helper/Searchers/KugouSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `final group = track.group; if (group != null && group.isNotEmpty)`。
library;

import '../providers/web/kugou/response.dart' as kg;
import '../providers/web/providers.dart';
import 'isearcher.dart';
import 'kugou_search_result.dart';
import 'searcher.dart';
import 'searchers.dart';

class KugouSearcher extends Searcher {
  @override
  String get name => 'Kugou';

  @override
  String get displayName => 'Kugou Music';

  @override
  Searchers get searcherType => Searchers.kugou;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    final search = <ISearchResult>[];

    try {
      final result = await Providers.kugouApi.getSearchSong(searchString);
      final results = result?.data?.info;
      if (results == null) return null;
      for (final track in results) {
        search.add(KugouSearchResult.fromSong(track));
        final group = track.group;
        if (group != null && group.isNotEmpty) {
          for (final subTrack in group) {
            search.add(KugouSearchResult.fromSong(subTrack));
          }
        }
      }
    } catch (_) {
      return null;
    }

    return search;
  }
}
