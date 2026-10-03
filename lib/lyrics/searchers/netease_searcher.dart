// Ported from Lyricify.Lyrics.Helper/Searchers/NeteaseSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../lyrics_log.dart';
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
    lyricsLog('[探针·网易云] 进入 searchForResults: 「$searchString」 useNew=$useNewSearchFirst');
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
        lyricsLog('[探针·网易云] 走旧接口 search()');
        result = await Providers.neteaseApi
            .search(searchString, ne.SearchTypeEnum.songId);
        lyricsLog('[探针·网易云] 旧接口返回 code=${result?.code} songs=${result?.result?.songs?.length}');
        if (result?.code == -460) throw Exception();
      } catch (e) {
        lyricsLog('[探针·网易云] 旧接口异常：$e');
        useNewSearchFirst = !useNewSearchFirst;
        try {
          result = await Providers.neteaseApi.searchNew(searchString);
          lyricsLog('[探针·网易云] 新接口返回 songs=${result?.result?.songs?.length}');
        } catch (e2) {
          lyricsLog('[探针·网易云] 新接口异常：$e2');
        }
      }
    }

    try {
      final results = result?.result.songs;
      lyricsLog('[探针·网易云] songs=${results?.length}');
      if (results == null) return null;
      for (final track in results) {
        search.add(NeteaseSearchResult.fromSong(track));
      }
      lyricsLog('[探针·网易云] 转成 ${search.length} 个 SearchResult');
    } catch (e) {
      lyricsLog('[探针·网易云] 转换异常: $e');
      return null;
    }

    return search;
  }
}
