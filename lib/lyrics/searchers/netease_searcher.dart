// Ported from Lyricify.Lyrics.Helper/Searchers/NeteaseSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../providers/web/netease/api.dart' as ne;
import '../providers/web/providers.dart';
import 'isearcher.dart';
import 'netease_search_result.dart';
import 'searcher.dart';
import 'searchers.dart';

class NeteaseSearcher extends Searcher {
  @override
  String get name => 'Netease';

  @override
  String get displayName => 'Netease Cloud Music';

  @override
  Searchers get searcherType => Searchers.netease;

  bool useNewSearchFirst = false;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    final search = <ISearchResult>[];

    dynamic? result;
    if (useNewSearchFirst) {
      try {
        result = await Providers.neteaseApi.searchNew(searchString);
      } catch (_) {
        useNewSearchFirst = !useNewSearchFirst;
        try {
          result = await Providers.neteaseApi
              .search(searchString, ne.SearchTypeEnum.songId);
          if (result.code == -460) throw Exception();
        } catch (_) {
          useNewSearchFirst = !useNewSearchFirst;
        }
      }
    } else {
      try {
        result = await Providers.neteaseApi
            .search(searchString, ne.SearchTypeEnum.songId);
        if (result?.code == -460) throw Exception();
      } catch (_) {
        useNewSearchFirst = !useNewSearchFirst;
        try {
          result = await Providers.neteaseApi.searchNew(searchString);
        } catch (_) {}
      }
    }

    try {
      final results = result?.result.songs;
      if (results == null) return null;
      for (final track in results) {
        search.add(NeteaseSearchResult.fromSong(track));
      }
    } catch (_) {
      return null;
    }

    return search;
  }
}
